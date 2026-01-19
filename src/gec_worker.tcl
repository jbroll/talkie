# gec_worker.tcl - GEC pipeline worker thread
# Processes text through grammar error correction in a dedicated thread
# Part of the pipeline: Engine → GEC → Output
#
# Flow:
#   Engine thread sends final results here
#   GEC worker processes text (homophone, punctcap, grammar)
#   Forwards processed text to Output thread
#   Sends UI notification to Main thread

source [file join [file dirname [info script]] worker.tcl]

namespace eval ::gec_worker {
    variable worker_name "gec"
    variable output_tid ""
    variable main_tid ""

    # Worker thread script
    variable worker_script {
        package require Thread

        namespace eval ::gec_worker::worker {
            variable initialized 0
            variable gec_ready 0
            variable main_tid ""
            variable output_tid ""
            variable script_dir ""

            proc init {main_tid_arg output_tid_arg script_dir_arg} {
                variable main_tid $main_tid_arg
                variable output_tid $output_tid_arg
                variable script_dir $script_dir_arg
                variable initialized
                variable gec_ready

                # Initialize config with defaults (will be synced from main thread)
                array set ::config {
                    gec_homophone 1
                    gec_punctcap 1
                    gec_grammar 0
                    confidence_threshold 100
                }

                # Set up auto_path for packages
                set gec_dir [file join $script_dir gec]
                lappend ::auto_path [file join $gec_dir lib]
                lappend ::auto_path [file join $script_dir wordpiece lib]
                if {[lsearch -exact $::auto_path "$::env(HOME)/.local/lib/tcllib2.0"] < 0} {
                    lappend ::auto_path "$::env(HOME)/.local/lib/tcllib2.0"
                }
                ::tcl::tm::path add "$::env(HOME)/lib/tcl8/site-tcl"

                # Load required packages
                package require json
                package require jbr::unix
                package require jbr::pipe

                # Source required files
                source [file join $script_dir textproc.tcl]
                source [file join $script_dir feedback.tcl]

                # Initialize feedback (for logging)
                ::feedback::init

                set initialized 1

                # Try to initialize GEC
                if {[catch {init_gec} err]} {
                    puts stderr "GEC worker: GEC init failed: $err"
                    set gec_ready 0
                } else {
                    set gec_ready 1
                }

                return [list status ok gec_ready $gec_ready]
            }

            proc init_gec {} {
                variable script_dir
                variable gec_ready

                # Source GEC modules
                set gec_dir [file join $script_dir gec]

                # Find model files
                set models_dir [file normalize [file join $script_dir ../models/gec]]
                set data_dir [file normalize [file join $script_dir ../data]]

                set punctcap_model [file join $models_dir distilbert-punct-cap.onnx]
                set homophone_model [file join $models_dir electra-small-generator.onnx]
                set grammar_model [file join $models_dir t5-grammar-ct2]
                set vocab_path [file join $gec_dir vocab.txt]
                set homophones_path [file join $data_dir homophones.json]

                # Verify required files exist
                foreach {name path} [list \
                    "Punctcap model" $punctcap_model \
                    "Homophone model" $homophone_model \
                    "Vocab" $vocab_path \
                    "Homophones" $homophones_path] {
                    if {![file exists $path]} {
                        error "Missing $name at $path"
                    }
                }

                # Check grammar model (optional)
                if {![file isdirectory $grammar_model]} {
                    puts stderr "GEC worker: Grammar model not found (Stage 3 disabled)"
                    set grammar_model ""
                }

                # Load pipeline
                source [file join $gec_dir pipeline.tcl]
                package require gec

                # Detect device
                set available_devices [gec::devices]
                set use_device "CPU"
                if {"NPU" in $available_devices} {
                    set use_device "NPU"
                }

                # Initialize pipeline
                gec_pipeline::init \
                    -punctcap_model $punctcap_model \
                    -homophone_model $homophone_model \
                    -grammar_model $grammar_model \
                    -vocab $vocab_path \
                    -homophones $homophones_path \
                    -device $use_device

                puts stderr "GEC worker: Initialized on $use_device"
                set gec_ready 1
            }

            # JSON helper - get nested value
            proc json_get {container args} {
                set current $container
                foreach step $args {
                    if {[string is integer -strict $step]} {
                        set current [lindex $current $step]
                    } else {
                        set current [dict get $current $step]
                    }
                }
                return $current
            }

            # Process raw JSON result from engine (entry point from pipeline)
            proc process_json {json_result vosk_ms} {
                variable initialized
                variable main_tid

                if {!$initialized} {
                    return
                }

                if {$json_result eq ""} {
                    return
                }

                # Parse JSON
                set result_dict [json::json2dict $json_result]

                # Skip partial results (shouldn't arrive here, but just in case)
                if {[dict exists $result_dict partial]} {
                    thread::send -async $main_tid [list ::audio::display_partial [dict get $result_dict partial]]
                    return
                }

                # Extract text and confidence from final result
                if {[dict exists $result_dict alternatives]} {
                    # N-best format
                    set text [json_get $result_dict alternatives 0 text]
                    set conf [json_get $result_dict alternatives 0 confidence]
                } elseif {[dict exists $result_dict text]} {
                    # MBR format
                    set text [dict get $result_dict text]
                    # Calculate average confidence
                    if {[dict exists $result_dict result]} {
                        set words [dict get $result_dict result]
                        set total_conf 0.0
                        set word_count 0
                        foreach word_info $words {
                            if {[dict exists $word_info conf]} {
                                set total_conf [expr {$total_conf + [dict get $word_info conf]}]
                                incr word_count
                            }
                        }
                        set conf [expr {$word_count > 0 ? ($total_conf / $word_count) * 100 : 100}]
                    } else {
                        set conf 100
                    }
                } else {
                    return
                }

                # Filter killwords
                set killwords {"" "the" "hm"}
                if {$text in $killwords} {
                    thread::send -async $main_tid [list ::audio::display_partial ""]
                    return
                }

                # Normalize confidence to 0-100 scale if needed
                if {$conf <= 1.0} {
                    set conf [expr {$conf * 100}]
                }

                # Filter by confidence threshold
                if {$conf < $::config(confidence_threshold)} {
                    puts stderr "GEC-FILTER: conf $conf < threshold $::config(confidence_threshold)"
                    thread::send -async $main_tid [list ::audio::display_partial ""]
                    return
                }

                # Process through GEC pipeline
                process_result $text $conf $vosk_ms
            }

            # Process a final result (after JSON parsing)
            # Runs GEC, forwards to output, notifies main thread
            proc process_result {text conf vosk_ms} {
                variable initialized
                variable gec_ready
                variable main_tid
                variable output_tid

                if {!$initialized} {
                    puts stderr "GEC worker: not initialized"
                    return
                }

                # Run GEC if ready and enabled
                set gec_timing {}
                if {$gec_ready} {
                    set original $text
                    set text [gec_process $text]
                    set gec_timing [gec_last_timing]

                    if {$text ne $original} {
                        puts stderr "GEC: '$original' -> '$text'"
                        ::feedback::gec $original $text
                    }
                }

                # Apply text processing (spacing, voice commands, etc.)
                set text [textproc $text]

                # Forward to output thread (next in pipeline)
                if {$text ne ""} {
                    ::feedback::inject $text
                    thread::send -async $output_tid [list ::output::worker::type_text $text]
                }

                # Notify main thread for UI update
                thread::send -async $main_tid [list ::audio::display_final $text $conf $vosk_ms $gec_timing]
            }

            # GEC processing with config checks
            proc gec_process {text} {
                variable gec_ready

                if {!$gec_ready || $text eq ""} {
                    return $text
                }

                # Access config from main thread's namespace isn't possible
                # So we check stages individually via pipeline
                return [gec_pipeline::process $text]
            }

            proc gec_last_timing {} {
                variable gec_ready
                if {!$gec_ready} {
                    return {}
                }
                return [gec_pipeline::last_timing]
            }

            # Update config values (called from main thread when config changes)
            proc update_config {key value} {
                # Store config locally for GEC stage checks
                set ::config($key) $value
            }

            proc cleanup {} {
                variable initialized
                variable gec_ready

                if {$gec_ready} {
                    catch { gec_pipeline::cleanup }
                    set gec_ready 0
                }
                set initialized 0
            }
        }
    }

    # Initialize GEC worker thread
    proc initialize {} {
        variable worker_name
        variable worker_script
        variable output_tid
        variable main_tid

        set main_tid [thread::id]

        # Get output thread ID (must be initialized first)
        set output_tid [::worker::tid "output"]
        if {$output_tid eq ""} {
            puts stderr "ERROR: Output worker must be initialized before GEC worker"
            return false
        }

        puts "Initializing GEC pipeline thread..."

        # Create worker thread
        set worker_tid [::worker::create $worker_name $worker_script]

        puts "  GEC worker thread: $worker_tid"
        puts "  Output thread: $output_tid"
        puts "  Main thread: $main_tid"

        # Initialize worker
        set response [::worker::send $worker_name [list ::gec_worker::worker::init \
            $main_tid $output_tid $::script_dir]]

        if {[dict get $response status] ne "ok"} {
            puts "ERROR: GEC worker initialization failed"
            ::worker::destroy $worker_name
            return false
        }

        set gec_ready [dict get $response gec_ready]

        puts "[expr {$gec_ready ? {+} : {-}}] GEC worker thread initialized"
        if {!$gec_ready} {
            puts "  WARNING: GEC models not loaded, corrections disabled"
        }

        # Sync initial config to worker
        sync_config

        return true
    }

    # Get worker thread ID (for engine to send results)
    proc tid {} {
        variable worker_name
        return [::worker::tid $worker_name]
    }

    # Sync config to worker thread
    proc sync_config {} {
        variable worker_name

        if {![::worker::exists $worker_name]} {
            return
        }

        # Send GEC-related config values
        foreach key {gec_homophone gec_punctcap gec_grammar confidence_threshold} {
            if {[info exists ::config($key)]} {
                ::worker::send_async $worker_name \
                    [list ::gec_worker::worker::update_config $key $::config($key)]
            }
        }
    }

    # Called when config changes
    proc on_config_change {key value} {
        variable worker_name

        if {![::worker::exists $worker_name]} {
            return
        }

        # Forward config change to worker
        ::worker::send_async $worker_name \
            [list ::gec_worker::worker::update_config $key $value]
    }

    # Cleanup
    proc cleanup {} {
        variable worker_name

        if {![::worker::exists $worker_name]} {
            return
        }

        puts "Cleaning up GEC worker thread..."
        ::worker::send $worker_name {::gec_worker::worker::cleanup}
        ::worker::destroy $worker_name
        puts "GEC worker cleanup complete"
    }
}
