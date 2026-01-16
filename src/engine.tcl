# engine.tcl - Integrated speech engine with direct audio processing
# Audio callbacks fire directly on the engine worker thread, eliminating
# the main thread from the audio processing path.

source [file join [file dirname [info script]] worker.tcl]
source [file join [file dirname [info script]] coprocess.tcl]

namespace eval ::engine {
    variable recognizer_cmd ""
    variable engine_name ""
    variable worker_name "engine"

    # Engine registry - central configuration
    variable engine_registry
    array set engine_registry {
        vosk,command      ""
        vosk,type         "critcl"
        vosk,model_dir    "vosk"
        vosk,model_config "vosk_modelfile"

        sherpa,command      "engines/sherpa_wrapper.sh"
        sherpa,type         "coprocess"
        sherpa,model_dir    "sherpa-onnx"
        sherpa,model_config "sherpa_modelfile"

        faster-whisper,command      "engines/faster_whisper_wrapper.sh"
        faster-whisper,type         "coprocess"
        faster-whisper,model_dir    "faster-whisper"
        faster-whisper,model_config "faster_whisper_modelfile"
    }

    # Check if engine is registered
    proc is_registered {engine_name} {
        variable engine_registry
        return [info exists engine_registry($engine_name,type)]
    }

    # Get engine property
    proc get_property {engine_name property} {
        variable engine_registry
        set key "${engine_name},${property}"
        if {[info exists engine_registry($key)]} {
            return $engine_registry($key)
        }
        return ""
    }

    # Worker namespace script - now includes audio processing
    variable worker_script {
        package require Thread

        namespace eval ::engine::worker {
            # Engine state
            variable engine_name ""
            variable engine_type ""
            variable recognizer ""
            variable main_tid ""
            variable script_dir ""

            # Audio state
            variable audio_stream ""
            variable audio_buffer_list {}
            variable this_speech_time 0
            variable last_speech_time 0
            variable last_ui_update_time 0
            variable transcribing 0

            # Config (copied from main thread)
            variable config
            array set config {}

            # Threshold state
            variable energy_buffer {}
            variable initialization_complete 0
            variable noise_floor 0
            variable noise_threshold 0

            proc init {main_tid_arg engine_name_arg engine_type_arg model_path sample_rate script_dir_arg config_dict} {
                variable main_tid $main_tid_arg
                variable engine_name $engine_name_arg
                variable engine_type $engine_type_arg
                variable recognizer
                variable script_dir $script_dir_arg
                variable config

                # Copy config from main thread
                array set config $config_dict

                if {[lsearch -exact $::auto_path "$::env(HOME)/.local/lib/tcllib2.0"] < 0} {
                    lappend ::auto_path "$::env(HOME)/.local/lib/tcllib2.0"
                }
                lappend ::auto_path [file join $script_dir pa lib pa]
                lappend ::auto_path [file join $script_dir vosk lib vosk]
                lappend ::auto_path [file join $script_dir audio lib audio]
                lappend ::auto_path [file join $script_dir uinput lib uinput]

                package require json
                package require pa
                package require audio

                if {$engine_type eq "critcl"} {
                    package require vosk
                    if {[info commands vosk::set_log_level] ne ""} {
                        vosk::set_log_level -1
                    }

                    if {[file exists $model_path]} {
                        set model [vosk::load_model -path $model_path]
                        set recognizer [$model create_recognizer -rate $sample_rate -alternatives 1]
                        return [json::dict2json {status ok message "Vosk worker initialized"}]
                    } else {
                        return [json::dict2json [list status error error "Model not found: $model_path"]]
                    }
                } elseif {$engine_type eq "coprocess"} {
                    source [file join $script_dir coprocess.tcl]

                    set cmd_path [file join $script_dir [lindex $model_path 0]]
                    set model_path_only [lindex $model_path 1]

                    set response [::coprocess::start $engine_name $cmd_path $model_path_only $sample_rate]
                    return $response
                } else {
                    return [json::dict2json [list status error error "Unknown engine type: $engine_type"]]
                }
            }

            # Start audio stream on this worker thread
            proc start_audio {device sample_rate frames_per_buffer chunk_seconds} {
                variable audio_stream
                variable config

                set config(audio_chunk_seconds) $chunk_seconds

                try {
                    set audio_stream [pa::open_stream \
                        -device $device \
                        -rate $sample_rate \
                        -channels 1 \
                        -frames $frames_per_buffer \
                        -format int16 \
                        -callback ::engine::worker::audio_callback]

                    $audio_stream start
                    return [list status ok]
                } on error message {
                    return [list status error message $message]
                }
            }

            proc stop_audio {} {
                variable audio_stream

                if {$audio_stream ne ""} {
                    try {
                        $audio_stream stop
                        $audio_stream close
                    } on error message {
                        puts stderr "stop audio stream: $message"
                    }
                    set audio_stream ""
                }
            }

            # Threshold detection (simplified, runs on worker)
            proc update_threshold {audiolevel} {
                variable energy_buffer
                variable initialization_complete
                variable noise_floor
                variable noise_threshold
                variable config
                variable main_tid

                lappend energy_buffer $audiolevel
                set energy_buffer [lrange $energy_buffer end-599 end]

                set init_samples [expr {int($config(initialization_samples))}]
                if {!$initialization_complete && [llength $energy_buffer] >= $init_samples} {
                    # Calculate noise floor from percentile
                    set sorted [lsort -real $energy_buffer]
                    set idx [expr {int([llength $sorted] * $config(noise_floor_percentile) / 100.0)}]
                    set noise_floor [lindex $sorted $idx]
                    set noise_threshold [expr {$noise_floor * $config(audio_threshold_multiplier)}]
                    set initialization_complete 1

                    # Notify main thread calibration complete
                    thread::send -async $main_tid [list after idle [list partial_text ""]]
                }
            }

            proc is_speech {audiolevel} {
                variable initialization_complete
                variable noise_threshold
                variable energy_buffer
                variable config
                variable main_tid

                update_threshold $audiolevel

                if {!$initialization_complete} {
                    set progress [expr {[llength $energy_buffer] * 100 / int($config(initialization_samples))}]
                    if {$progress % 20 == 0} {
                        thread::send -async $main_tid [list after idle [list partial_text "Calibrating... ${progress}%"]]
                    }
                    return 0
                }

                return [expr {$audiolevel > $noise_threshold}]
            }

            # Audio callback - runs directly on this worker thread
            proc audio_callback {stream_name timestamp data} {
                variable this_speech_time
                variable last_speech_time
                variable audio_buffer_list
                variable last_ui_update_time
                variable transcribing
                variable recognizer
                variable engine_type
                variable engine_name
                variable main_tid
                variable config

                try {
                    set audiolevel [audio::energy $data int16]
                    set speech [is_speech $audiolevel]

                    # Throttle UI updates to ~5Hz
                    set now [clock milliseconds]
                    if {$now - $last_ui_update_time >= 200} {
                        thread::send -async $main_tid [list ::engine::update_ui $audiolevel $speech]
                        set last_ui_update_time $now
                    }

                    if {$transcribing} {
                        set callbacks_per_sec [expr {1.0 / $config(audio_chunk_seconds)}]
                        set lookback_frames [expr {int($config(lookback_seconds) * $callbacks_per_sec + 0.5)}]
                        lappend audio_buffer_list $data
                        set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]

                        if {$recognizer eq ""} {
                            set audio_buffer_list {}
                            return
                        }

                        # Rising edge of speech - send lookback buffer
                        if {$speech && !$last_speech_time} {
                            set this_speech_time $timestamp
                            foreach chunk $audio_buffer_list {
                                process_chunk $chunk
                            }
                            set last_speech_time $timestamp
                        } elseif {$last_speech_time} {
                            # Ongoing speech - process current chunk
                            process_chunk $data

                            if {$speech} {
                                set last_speech_time $timestamp
                            } else {
                                # Check for silence timeout
                                if {$last_speech_time + $config(silence_seconds) < $timestamp} {
                                    process_final

                                    set speech_duration [expr {$last_speech_time - $this_speech_time}]
                                    if {$speech_duration <= $config(min_duration)} {
                                        thread::send -async $main_tid [list after idle [list partial_text ""]]
                                    }

                                    set last_speech_time 0
                                    set audio_buffer_list {}
                                }
                            }
                        }
                    }
                } on error message {
                    puts stderr "audio callback: $message"
                }
            }

            proc process_chunk {chunk} {
                variable recognizer
                variable engine_type
                variable engine_name
                variable main_tid

                try {
                    if {$engine_type eq "critcl"} {
                        set result [$recognizer process $chunk]
                    } else {
                        set result [::coprocess::process $engine_name $chunk]
                    }

                    if {$result ne ""} {
                        thread::send -async $main_tid [list ::audio::parse_and_display_result $result]
                    }
                } on error {err info} {
                    puts stderr "Worker process error: $err"
                }
            }

            proc process_final {} {
                variable recognizer
                variable engine_type
                variable engine_name
                variable main_tid

                try {
                    set start_us [clock microseconds]
                    if {$engine_type eq "critcl"} {
                        set result [$recognizer final-result]
                    } else {
                        set result [::coprocess::final $engine_name]
                    }
                    set vosk_ms [expr {([clock microseconds] - $start_us) / 1000.0}]

                    if {$result ne ""} {
                        thread::send -async $main_tid [list ::audio::parse_and_display_result $result $vosk_ms]
                    }
                } on error {err info} {
                    puts stderr "Worker final error: $err"
                }
            }

            proc set_transcribing {value} {
                variable transcribing
                variable last_speech_time
                variable audio_buffer_list
                variable recognizer

                set transcribing $value
                if {!$value} {
                    set last_speech_time 0
                    set audio_buffer_list {}
                    if {$recognizer ne ""} {
                        catch {
                            if {[info commands $recognizer] ne ""} {
                                $recognizer reset
                            }
                        }
                    }
                }
            }

            proc reset {} {
                variable recognizer
                variable engine_type
                variable engine_name
                variable last_speech_time
                variable audio_buffer_list

                set last_speech_time 0
                set audio_buffer_list {}

                try {
                    if {$engine_type eq "critcl"} {
                        $recognizer reset
                    } else {
                        ::coprocess::reset $engine_name
                    }
                } on error {err info} {
                    puts stderr "Worker reset error: $err"
                }
            }

            proc close {} {
                variable recognizer
                variable engine_type
                variable engine_name

                stop_audio

                try {
                    if {$engine_type eq "critcl"} {
                        if {$recognizer ne "" && [info commands $recognizer] ne ""} {
                            catch {rename $recognizer ""}
                        }
                    } else {
                        ::coprocess::stop $engine_name
                    }
                } on error {err info} {
                    puts stderr "Worker close error: $err"
                }
            }
        }
    }

    # Called from worker thread to update UI variables
    proc update_ui {audiolevel is_speech} {
        set ::audiolevel $audiolevel
        set ::is_speech $is_speech
    }

    # Initialize engine with integrated audio
    proc initialize {} {
        variable recognizer_cmd
        variable engine_name
        variable worker_name
        variable worker_script

        set engine_name $::config(speech_engine)

        # Check if engine is registered
        if {![is_registered $engine_name]} {
            puts "ERROR: Unknown engine: $engine_name"
            return false
        }

        set engine_type [get_property $engine_name type]
        set main_tid [thread::id]

        puts "Initializing $engine_name engine (type: $engine_type) with integrated audio..."

        # Create worker thread using worker module
        set worker_tid [::worker::create $worker_name $worker_script]

        # Prepare model path based on engine type
        if {$engine_type eq "critcl"} {
            if {$engine_name eq "vosk"} {
                set model_path [get_model_path $::config(vosk_modelfile)]
                if {$model_path eq "" || ![file exists $model_path]} {
                    puts "ERROR: Vosk model not found"
                    ::worker::destroy $worker_name
                    return false
                }
            } else {
                puts "ERROR: Unknown critcl engine: $engine_name"
                ::worker::destroy $worker_name
                return false
            }
        } elseif {$engine_type eq "coprocess"} {
            set cmd [get_property $engine_name command]
            set model_config [get_property $engine_name model_config]
            set model_dir [get_property $engine_name model_dir]

            if {$model_config ne "" && [info exists ::config($model_config)]} {
                set modelfile $::config($model_config)
                set model_path_full [file join [file dirname $::script_dir] models $model_dir $modelfile]
            } else {
                set model_path_full [file join [file dirname $::script_dir] models $model_dir]
            }

            set model_path [list $cmd $model_path_full]
        } else {
            puts "ERROR: Unknown engine type: $engine_type"
            ::worker::destroy $worker_name
            return false
        }

        puts "  Worker thread: $worker_tid"
        puts "  Main thread: $main_tid"
        puts "  Model path: $model_path"
        puts "  Sample rate: $::device_sample_rate"

        # Convert config array to dict for passing to worker
        set config_dict [array get ::config]

        # Initialize worker thread with engine
        set response [::worker::send $worker_name [list ::engine::worker::init \
            $main_tid $engine_name $engine_type $model_path $::device_sample_rate $::script_dir $config_dict]]

        # Parse response
        set response_dict [json::json2dict $response]

        if {![dict exists $response_dict status] || [dict get $response_dict status] ne "ok"} {
            if {[dict exists $response_dict error]} {
                puts "ERROR: Worker initialization failed: [dict get $response_dict error]"
            } else {
                puts "ERROR: Worker initialization failed: $response"
            }
            ::worker::destroy $worker_name
            return false
        }

        puts "✓ Engine initialized"
        if {[dict exists $response_dict message]} {
            puts "  [dict get $response_dict message]"
        }

        # Start audio stream on worker thread
        puts "Starting audio stream on engine thread..."
        set audio_response [::worker::send $worker_name [list ::engine::worker::start_audio \
            $::config(input_device) $::device_sample_rate $::device_frames_per_buffer $::audio_chunk_seconds]]

        if {[dict get $audio_response status] ne "ok"} {
            puts "ERROR: Failed to start audio: [dict get $audio_response message]"
            ::worker::destroy $worker_name
            return false
        }

        puts "✓ Audio stream running on engine thread"

        return true
    }

    # Set transcribing state on worker
    proc set_transcribing {value} {
        variable worker_name
        if {[::worker::exists $worker_name]} {
            ::worker::send_async $worker_name [list ::engine::worker::set_transcribing $value]
        }
    }

    # Reset recognizer
    proc reset {} {
        variable worker_name
        if {[::worker::exists $worker_name]} {
            ::worker::send_async $worker_name {::engine::worker::reset}
        }
    }

    # Cleanup
    proc cleanup {} {
        variable engine_name
        variable worker_name

        # Safety check - if engine_name is empty, nothing to cleanup
        if {$engine_name eq ""} {
            return
        }

        puts "Cleaning up $engine_name engine..."

        # Close worker (will stop audio and release recognizer)
        if {[::worker::exists $worker_name]} {
            ::worker::send $worker_name {::engine::worker::close}
            ::worker::destroy $worker_name
        }

        set engine_name ""
        puts "Cleanup complete"
    }

    # Legacy API - recognizer proxy (now returns empty, not needed)
    proc recognizer {} {
        return ""
    }

    # Get current engine name
    proc current {} {
        variable engine_name
        return $engine_name
    }
}
