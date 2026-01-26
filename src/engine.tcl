# engine.tcl - Decoupled audio capture and speech processing
# Two worker threads:
#   1. Audio worker: captures audio, queues to processing (never blocks)
#   2. Processing worker: VAD, Vosk, sends results to GEC
#
# This architecture ensures audio capture is never blocked by Vosk latency.

source [file join [file dirname [info script]] worker.tcl]
source [file join [file dirname [info script]] coprocess.tcl]

namespace eval ::engine {
    variable recognizer_cmd ""
    variable engine_name ""
    variable audio_worker_name "audio"
    variable processing_worker_name "processing"

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

    # Audio worker script - minimal, just captures and queues
    variable audio_worker_script {
        package require Thread

        namespace eval ::audio::worker {
            variable processing_tid ""
            variable audio_stream ""
            variable script_dir ""

            proc init {processing_tid_arg script_dir_arg} {
                variable processing_tid $processing_tid_arg
                variable script_dir $script_dir_arg

                lappend ::auto_path [file join $script_dir pa lib pa]
                package require pa
            }

            proc start_audio {device sample_rate frames_per_buffer} {
                variable audio_stream

                try {
                    set audio_stream [pa::open_stream \
                        -device $device \
                        -rate $sample_rate \
                        -channels 1 \
                        -frames $frames_per_buffer \
                        -format int16 \
                        -callback ::audio::worker::audio_callback]

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

            # Audio callback - absolute minimum work
            proc audio_callback {stream_name timestamp data} {
                variable processing_tid

                # ONE thing only: queue raw audio to processing thread
                thread::send -async $processing_tid \
                    [list ::processing::worker::process_audio $timestamp $data]
            }

            proc close {} {
                stop_audio
            }
        }
    }

    # Processing worker script - VAD, Vosk, results
    variable processing_worker_script {
        package require Thread

        namespace eval ::processing::worker {
            # Engine state
            variable engine_name ""
            variable engine_type ""
            variable recognizer ""
            variable main_tid ""
            variable gec_tid ""
            variable script_dir ""

            # Audio state
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
            variable last_is_speech_ms 0
            variable last_segment_end_ms 0

            # Health monitoring state
            variable last_callback_time 0
            variable last_audiolevel 0.0
            variable level_change_count 0

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
                lappend ::auto_path [file join $script_dir vosk lib vosk]
                lappend ::auto_path [file join $script_dir audio lib audio]

                package require json
                package require audio

                if {$engine_type eq "critcl"} {
                    package require vosk
                    if {[info commands vosk::set_log_level] ne ""} {
                        vosk::set_log_level -1
                    }

                    if {[file exists $model_path]} {
                        set model [vosk::load_model -path $model_path]
                        set recognizer [$model create_recognizer -rate $sample_rate -alternatives 1]
                        return [json::dict2json {status ok message "Processing worker initialized"}]
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

            # Threshold detection
            proc update_threshold {audiolevel} {
                variable energy_buffer
                variable initialization_complete
                variable noise_floor
                variable noise_threshold
                variable config
                variable main_tid

                lappend energy_buffer $audiolevel
                set energy_buffer [lrange $energy_buffer end-599 end]

                set buf_len [llength $energy_buffer]
                set init_samples [expr {int($config(initialization_samples))}]

                if {!$initialization_complete && $buf_len >= $init_samples} {
                    # Initial calibration
                    calculate_noise_floor
                    set initialization_complete 1
                    thread::send -async $main_tid [list after idle [list partial_text ""]]
                } elseif {$initialization_complete && $buf_len % 50 == 0} {
                    # Continuous recalculation every 50 samples
                    calculate_noise_floor
                }
            }

            proc calculate_noise_floor {} {
                variable energy_buffer
                variable noise_floor
                variable noise_threshold
                variable config

                set sorted [lsort -real $energy_buffer]
                set count [llength $sorted]
                if {$count < 10} return

                set idx [expr {int($count * $config(noise_floor_percentile) / 100.0)}]
                set noise_floor [lindex $sorted $idx]
                set noise_threshold [expr {$noise_floor * $config(audio_threshold_multiplier)}]
            }

            proc is_speech {audiolevel} {
                variable initialization_complete
                variable noise_threshold
                variable energy_buffer
                variable config
                variable main_tid
                variable last_speech_time
                variable last_is_speech_ms
                variable last_segment_end_ms

                update_threshold $audiolevel

                if {!$initialization_complete} {
                    set progress [expr {[llength $energy_buffer] * 100 / int($config(initialization_samples))}]
                    if {$progress % 20 == 0} {
                        thread::send -async $main_tid [list after idle [list partial_text "Calibrating... ${progress}%"]]
                    }
                    return 0
                }

                set in_segment [expr {$last_speech_time != 0}]
                set current_ms [clock milliseconds]

                # Track when segments transition from active to inactive
                if {!$in_segment && $last_is_speech_ms > 0} {
                    set last_segment_end_ms $current_ms
                    set last_is_speech_ms 0
                }

                set raw_is_speech [expr {$audiolevel > $noise_threshold}]
                set is_speech $raw_is_speech

                # Spike suppression: Prevent noise spikes from starting new segments
                # Only suppress spikes trying to START a new segment shortly after previous ended
                # (Removed CASE 1 which incorrectly suppressed resumed speech mid-segment)
                if {!$in_segment && $raw_is_speech && $last_segment_end_ms > 0} {
                    set time_since_end [expr {($current_ms - $last_segment_end_ms) / 1000.0}]
                    if {$time_since_end < $config(spike_suppression_seconds)} {
                        set is_speech 0
                    }
                }

                # Update last speech time when we have confirmed speech
                if {$is_speech} {
                    set last_is_speech_ms $current_ms
                }

                return $is_speech
            }

            # Process audio chunk from audio worker
            proc process_audio {timestamp data} {
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
                variable noise_floor
                variable noise_threshold
                variable last_callback_time
                variable last_audiolevel
                variable level_change_count

                try {
                    # Compute energy here (not in audio thread)
                    set audiolevel [audio::energy $data int16]

                    # Health monitoring: track audio level changes
                    # Only count changes > 1.0 as "real" (filters out quiet room noise)
                    if {abs($audiolevel - $last_audiolevel) > 1.0} {
                        set last_callback_time [clock seconds]
                        incr level_change_count
                    }
                    set last_audiolevel $audiolevel

                    set speech [is_speech $audiolevel]

                    # Throttle UI updates to ~5Hz
                    set now [clock milliseconds]
                    if {$now - $last_ui_update_time >= 200} {
                        thread::send -async $main_tid [list ::engine::update_ui $audiolevel $speech $noise_floor $noise_threshold]
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
                            puts stderr "SEGMENT-START: timestamp=$timestamp"
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
                                # In silence - check for timeout
                                set silence_elapsed [expr {$timestamp - $last_speech_time}]
                                if {$silence_elapsed > $config(silence_seconds)} {
                                    process_final

                                    set speech_duration [expr {$last_speech_time - $this_speech_time}]
                                    if {$speech_duration <= $config(min_duration)} {
                                        puts stderr "SEGMENT-SHORT: duration=$speech_duration <= min=$config(min_duration), clearing"
                                        thread::send -async $main_tid [list after idle [list partial_text ""]]
                                    }

                                    set last_speech_time 0
                                    set audio_buffer_list {}
                                }
                            }
                        }
                    }
                } on error message {
                    puts stderr "processing worker: $message"
                }
            }

            proc process_chunk {chunk} {
                variable recognizer
                variable engine_type
                variable engine_name
                variable main_tid

                try {
                    set start_us [clock microseconds]
                    if {$engine_type eq "critcl"} {
                        set result [$recognizer process $chunk]
                    } else {
                        set result [::coprocess::process $engine_name $chunk]
                    }

                    # Extract partial text and send to main thread for display
                    if {$result ne ""} {
                        set result_dict [json::json2dict $result]
                        if {[dict exists $result_dict partial]} {
                            set partial_text [dict get $result_dict partial]
                            thread::send -async $main_tid [list ::audio::display_partial $partial_text]
                        }
                    }
                } on error {err info} {
                    puts stderr "Processing worker process error: $err"
                }
            }

            proc process_final {} {
                variable recognizer
                variable engine_type
                variable engine_name
                variable main_tid
                variable gec_tid

                puts stderr "SEGMENT-END: calling final-result"

                try {
                    set start_us [clock microseconds]
                    if {$engine_type eq "critcl"} {
                        set result [$recognizer final-result]
                    } else {
                        set result [::coprocess::final $engine_name]
                    }
                    set vosk_ms [expr {([clock microseconds] - $start_us) / 1000.0}]

                    if {$result ne ""} {
                        # Send final results to GEC thread (required)
                        thread::send -async $gec_tid [list ::gec_worker::worker::process_json $result $vosk_ms]
                    } else {
                        puts stderr "SEGMENT-END: empty result from recognizer"
                    }
                } on error {err info} {
                    puts stderr "Processing worker final error: $err"
                }
            }

            proc set_gec_tid {tid} {
                variable gec_tid
                set gec_tid $tid
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
                    puts stderr "Processing worker reset error: $err"
                }
            }

            proc update_config {key value} {
                variable config
                set config($key) $value
            }

            # Health monitoring: get status and reset counter
            proc get_health_status {} {
                variable last_callback_time
                variable level_change_count

                set status [list \
                    last_callback_time $last_callback_time \
                    level_change_count $level_change_count]

                # Reset counter after check
                set level_change_count 0

                return $status
            }

            proc close {} {
                variable recognizer
                variable engine_type
                variable engine_name

                try {
                    if {$engine_type eq "critcl"} {
                        if {$recognizer ne "" && [info commands $recognizer] ne ""} {
                            catch {rename $recognizer ""}
                        }
                    } else {
                        ::coprocess::stop $engine_name
                    }
                } on error {err info} {
                    puts stderr "Processing worker close error: $err"
                }
            }
        }
    }

    # Called from worker thread to update UI variables
    proc update_ui {audiolevel is_speech noise_floor noise_threshold} {
        set ::audiolevel $audiolevel
        set ::is_speech $is_speech
        set ::threshold_noise_floor $noise_floor
        set ::threshold_noise_threshold $noise_threshold
        # Estimate speechlevel as 3x noise threshold (reasonable default)
        if {![info exists ::threshold_speechlevel] || $::threshold_speechlevel < $noise_threshold} {
            set ::threshold_speechlevel [expr {$noise_threshold * 3}]
        }
        # Update UI ranges if the proc exists
        if {[info commands ::update_audio_ranges] ne ""} {
            ::update_audio_ranges
        }
    }

    # Initialize engine with decoupled audio capture
    proc initialize {} {
        variable recognizer_cmd
        variable engine_name
        variable audio_worker_name
        variable processing_worker_name
        variable audio_worker_script
        variable processing_worker_script

        set engine_name $::config(speech_engine)

        # Check if engine is registered
        if {![is_registered $engine_name]} {
            puts "ERROR: Unknown engine: $engine_name"
            return false
        }

        set engine_type [get_property $engine_name type]
        set main_tid [thread::id]

        puts "Initializing $engine_name engine (type: $engine_type) with decoupled audio..."

        # Prepare model path based on engine type
        if {$engine_type eq "critcl"} {
            if {$engine_name eq "vosk"} {
                set model_path [get_model_path $::config(vosk_modelfile)]
                if {$model_path eq "" || ![file exists $model_path]} {
                    puts "ERROR: Vosk model not found"
                    return false
                }
            } else {
                puts "ERROR: Unknown critcl engine: $engine_name"
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
            return false
        }

        # Step 1: Create processing worker (needs main TID, loads Vosk)
        puts "Creating processing worker..."
        set processing_tid [::worker::create $processing_worker_name $processing_worker_script]
        puts "  Processing thread: $processing_tid"

        # Convert config array to dict for passing to worker
        # Include audio_chunk_seconds which is a separate global
        set config_dict [array get ::config]
        lappend config_dict audio_chunk_seconds $::audio_chunk_seconds

        # Initialize processing worker with engine
        set response [::worker::send $processing_worker_name [list ::processing::worker::init \
            $main_tid $engine_name $engine_type $model_path $::device_sample_rate $::script_dir $config_dict]]

        # Parse response
        set response_dict [json::json2dict $response]

        if {![dict exists $response_dict status] || [dict get $response_dict status] ne "ok"} {
            if {[dict exists $response_dict error]} {
                puts "ERROR: Processing worker initialization failed: [dict get $response_dict error]"
            } else {
                puts "ERROR: Processing worker initialization failed: $response"
            }
            ::worker::destroy $processing_worker_name
            return false
        }

        puts "  [dict get $response_dict message]"

        # Step 2: Create audio worker (needs processing TID)
        puts "Creating audio worker..."
        set audio_tid [::worker::create $audio_worker_name $audio_worker_script]
        puts "  Audio thread: $audio_tid"

        # Initialize audio worker with processing thread ID
        ::worker::send $audio_worker_name [list ::audio::worker::init $processing_tid $::script_dir]

        # Step 3: Start audio stream on audio worker
        puts "Starting audio stream..."
        set audio_response [::worker::send $audio_worker_name [list ::audio::worker::start_audio \
            $::config(input_device) $::device_sample_rate $::device_frames_per_buffer]]

        if {[dict get $audio_response status] ne "ok"} {
            puts "ERROR: Failed to start audio: [dict get $audio_response message]"
            ::worker::destroy $audio_worker_name
            ::worker::destroy $processing_worker_name
            return false
        }

        puts "✓ Audio capture running (decoupled from processing)"
        puts "  Main thread: $main_tid"
        puts "  Model path: $model_path"
        puts "  Sample rate: $::device_sample_rate"

        # Start health monitoring for frozen stream detection
        start_health_monitoring

        return true
    }

    # Set transcribing state on processing worker
    proc set_transcribing {value} {
        variable processing_worker_name
        if {[::worker::exists $processing_worker_name]} {
            ::worker::send_async $processing_worker_name [list ::processing::worker::set_transcribing $value]
        }
    }

    # Set GEC worker thread ID (for pipeline: Processing → GEC → Output)
    proc set_gec_tid {tid} {
        variable processing_worker_name
        if {[::worker::exists $processing_worker_name]} {
            ::worker::send_async $processing_worker_name [list ::processing::worker::set_gec_tid $tid]
        }
    }

    # Reset recognizer
    proc reset {} {
        variable processing_worker_name
        if {[::worker::exists $processing_worker_name]} {
            ::worker::send_async $processing_worker_name {::processing::worker::reset}
        }
    }

    # Propagate config change to processing worker
    proc on_config_change {key value} {
        variable processing_worker_name
        if {[::worker::exists $processing_worker_name]} {
            ::worker::send_async $processing_worker_name [list ::processing::worker::update_config $key $value]
        }
    }

    # Restart audio stream with new device settings
    proc restart_audio {device sample_rate frames_per_buffer} {
        variable audio_worker_name

        if {[::worker::exists $audio_worker_name]} {
            # Stop current stream
            ::worker::send $audio_worker_name {::audio::worker::stop_audio}

            # Start new stream with updated settings
            set response [::worker::send $audio_worker_name [list ::audio::worker::start_audio \
                $device $sample_rate $frames_per_buffer]]

            if {[dict get $response status] ne "ok"} {
                puts stderr "Failed to restart audio: [dict get $response message]"
                return false
            }
            puts "Audio stream restarted with device: $device"
        }
        return true
    }

    # Cleanup
    proc cleanup {} {
        variable engine_name
        variable audio_worker_name
        variable processing_worker_name

        # Stop health monitoring
        stop_health_monitoring

        # Safety check - if engine_name is empty, nothing to cleanup
        if {$engine_name eq ""} {
            return
        }

        puts "Cleaning up $engine_name engine..."

        # Stop audio first
        if {[::worker::exists $audio_worker_name]} {
            ::worker::send $audio_worker_name {::audio::worker::close}
            ::worker::destroy $audio_worker_name
        }

        # Then stop processing
        if {[::worker::exists $processing_worker_name]} {
            ::worker::send $processing_worker_name {::processing::worker::close}
            ::worker::destroy $processing_worker_name
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

    # Health monitoring - detect frozen audio streams
    variable health_timer ""
    variable health_check_interval 30000  ;# 30 seconds

    proc start_health_monitoring {} {
        variable health_timer
        variable health_check_interval

        # Cancel any existing timer
        stop_health_monitoring

        # Schedule periodic health check
        set health_timer [after $health_check_interval ::engine::check_stream_health]
    }

    proc stop_health_monitoring {} {
        variable health_timer

        if {$health_timer ne ""} {
            after cancel $health_timer
            set health_timer ""
        }
    }

    proc check_stream_health {} {
        variable processing_worker_name
        variable health_timer
        variable health_check_interval

        # Get health status from processing worker
        if {![::worker::exists $processing_worker_name]} {
            set health_timer [after $health_check_interval ::engine::check_stream_health]
            return
        }

        set status [::worker::send $processing_worker_name {::processing::worker::get_health_status}]
        set last_time [dict get $status last_callback_time]
        set change_count [dict get $status level_change_count]

        # Check if stream appears frozen:
        # - More than 30 seconds since last level change
        # - AND fewer than 3 level changes in the check period
        set time_since_change [expr {[clock seconds] - $last_time}]

        if {$last_time > 0 && $time_since_change > 30 && $change_count < 3} {
            puts stderr "Audio stream appears frozen (${time_since_change}s since change, $change_count changes) - restarting"
            ::audio::restart_audio_stream
        }

        # Schedule next check
        set health_timer [after $health_check_interval ::engine::check_stream_health]
    }
}
