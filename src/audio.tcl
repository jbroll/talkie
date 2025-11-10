proc ::tcl::mathfunc::clip {min val max} {
    expr {($val < $min) ? $min : (($val > $max) ? $max : $val)}
}

namespace eval ::audio {
    variable audio_stream ""
    variable audio_buffer_list {}
    variable this_speech_time 0
    variable last_speech_time 0

    # Health monitoring variables
    variable last_callback_time 0
    variable last_audiolevel 0
    variable level_change_count 0
    variable health_timer ""

    proc audio_callback {stream_name timestamp data} {
        variable this_speech_time
        variable last_speech_time
        variable audio_buffer_list
        variable last_callback_time
        variable last_audiolevel
        variable level_change_count

        try {
            set audiolevel [audio::energy $data int16]
            set ::audiolevel $audiolevel

            # Track significant level changes (variance > 1.0)
            if {abs($audiolevel - $last_audiolevel) > 1.0} {
                incr level_change_count
                # Update health monitoring timestamp only when we see data changes
                set last_callback_time [clock seconds]
            }
            set last_audiolevel $audiolevel

            set is_speech [threshold::is_speech $audiolevel $last_speech_time]
            set ::is_speech $is_speech

            if {$::transcribing} {
                set lookback_frames [expr {int($::config(lookback_seconds) * 10 + 0.5)}]
                lappend audio_buffer_list $data
                set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]

                set recognizer [::engine::recognizer]
                if {$recognizer eq ""} {
                    set audio_buffer_list {}
                    return
                }

                # Rising edge of speech - send lookback buffer
                if {$is_speech && !$last_speech_time} {
                set this_speech_time $timestamp
                foreach chunk $audio_buffer_list {
                $recognizer process-async $chunk
                }
                set last_speech_time $timestamp
                } elseif {$last_speech_time} {
                # Ongoing speech - send current chunk
                $recognizer process-async $data

                    if {$is_speech} {
                    set last_speech_time $timestamp
                } else {
                # Check for silence timeout
                        if {$last_speech_time + $::config(silence_seconds) < $timestamp} {
                    $recognizer final-async

                set speech_duration [expr {$last_speech_time - $this_speech_time}]
                if {$speech_duration <= $::config(min_duration)} {
                        after idle [partial_text ""]
                                # print THRS-SHORTS $speech_duration
                    }

                        set last_speech_time 0
                            set audio_buffer_list {}
                        }
                    }
                }
            }
        } on error message {
            puts "audio callback: $message\n$::errorInfo"
        }
    }

    proc json-get {container args} {
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

    set ::killwords { "" "the" "hm" }

    proc parse_and_display_result { result } {
        if { $result eq "" } { return }

        set result_dict [json::json2dict $result]

        if {[dict exists $result_dict partial]} {
            | { dict get $result_dict partial | textproc | partial_text }
            return
        }

        set text [json-get $result_dict alternatives 0 text]
        set conf [json-get $result_dict alternatives 0 confidence]

        if { [lsearch -exact $::killwords $text] < 0 } {
            if { [threshold::accept $conf] } {
                set text [textproc $text]
                ::output::type_async $text
                after idle [final_text $text $conf]
            }
            set ::confidence $conf
        }
        after idle [partial_text ""]
    }

    proc check_stream_health {} {
        variable last_callback_time
        variable level_change_count
        variable health_timer
        variable audio_stream

        set now [clock seconds]
        set time_since_data [expr {$now - $last_callback_time}]

        # Only check health if stream exists
        if {$audio_stream ne ""} {
            # Detect frozen stream: no data for 30s AND almost no level changes
            # This indicates device stopped streaming (e.g., after suspend/resume)
            if {$time_since_data > 30 && $level_change_count < 3} {
                puts "⚠️  Audio stream frozen (no data for ${time_since_data}s, ${level_change_count} level changes)"
                puts "🔄 Re-enumerating devices and restarting stream..."
                restart_audio_stream
                set last_callback_time $now
                set level_change_count 0
            }
        }

        # Reset level change counter for next interval
        set level_change_count 0

        # Schedule next health check in 10 seconds
        set health_timer [after 10000 ::audio::check_stream_health]
    }

    proc start_health_monitoring {} {
        variable health_timer
        variable last_callback_time
        variable level_change_count

        set last_callback_time [clock seconds]
        set level_change_count 0

        # Cancel any existing timer
        if {$health_timer ne ""} {
            after cancel $health_timer
        }

        # Start periodic health checks every 10 seconds
        set health_timer [after 10000 ::audio::check_stream_health]
    }

    proc stop_health_monitoring {} {
        variable health_timer

        if {$health_timer ne ""} {
            after cancel $health_timer
            set health_timer ""
        }
    }

    proc start_audio_stream {} {
        variable audio_stream

        try {
            set audio_stream [pa::open_stream \
                -device $::config(input_device) \
                -rate $::device_sample_rate \
                -channels 1 \
                -frames $::device_frames_per_buffer \
                -format int16 \
                -callback ::audio::audio_callback]

            $audio_stream start

            # Start health monitoring after successful stream start
            start_health_monitoring

        } on error message {
            puts "start audio stream: $message"
            set audio_stream ""
        }
    }

    proc stop_audio_stream {} {
        variable audio_stream

        # Stop health monitoring first
        stop_health_monitoring

        if {$audio_stream ne ""} {
            try {
                $audio_stream stop
                $audio_stream close
            } on error message {
                puts "stop audio stream: $message"
            }
            set audio_stream ""
        }
    }

    proc restart_audio_stream {} {
        stop_audio_stream
        ::audio::refresh_devices
        start_audio_stream
    }

    proc start_transcription {} {
        variable audio_buffer_list
        variable last_speech_time

        if {![threshold::ready]} {
            return false
        }

        set audio_buffer_list {}
        set last_speech_time 0

        [::engine::recognizer] reset
        textproc_reset
        threshold::reset

        set ::transcribing 1
        state_save $::transcribing
        return true
    }

    proc stop_transcription {} {
        variable last_speech_time
        variable audio_buffer_list

        set ::transcribing 0
        state_save $::transcribing
        
        # Reset worker thread recognizer
        set recognizer [::engine::recognizer]
        if {$recognizer ne ""} {
            catch {$recognizer reset}
        }
        
        set last_speech_time 0
        set audio_buffer_list {}
    }

    proc toggle_transcription {} {
        set ::transcribing [expr {!$::transcribing}]
        state_save $::transcribing
        return $::transcribing
    }

    proc initialize {} {
        if {![::engine::initialize]} {
            puts "Failed to initialize speech engine"
            return false
        }

        start_audio_stream

        set ::transcribing [state_load]

        if {$::transcribing} {
            start_transcription
        }

        return true
    }

    proc refresh_devices {} {
            set input_device ""
            set input_devices {}
            set device_info_map {}
            set device_sample_rate 16000
            set preferred $::config(input_device)

            # Build lookup table of device name -> info in single pass
            foreach device [pa::list_devices] {
                if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                    set name [dict get $device name]
                    set sample_rate [dict get $device defaultSampleRate]

                    lappend input_devices $name
                    dict set device_info_map $name $sample_rate

                    if {$name eq $preferred || [string match "*$preferred*" $name]} {
                        set input_device $name
                        set device_sample_rate $sample_rate
                        set found_preferred true
                    }
                }
            }

            # Use first available device if preferred not found
            if {$input_device eq "" && [llength $input_devices] > 0} {
                set ::config(input_device) [lindex $input_devices 0]
                set input_device $::config(input_device)
                set device_sample_rate [dict get $device_info_map $input_device]
            }

            set ::input_device $input_device
            set ::input_devices $input_devices
            set ::device_info_map $device_info_map
            set ::device_sample_rate $device_sample_rate

            # Calculate frames_per_buffer as ~100ms worth of frames
            set ::device_frames_per_buffer [expr {int($device_sample_rate * 0.1)}]
    }
}
