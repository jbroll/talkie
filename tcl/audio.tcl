namespace eval ::audio {
    variable audio_stream ""
    variable audio_buffer_list {}
    variable last_speech_time 0
    variable speech_energy_sum 0
    variable speech_energy_count 0
    variable average_speech_energy 0
    variable energy_buffer {}
    variable noise_floor 0
    variable speech_floor 0
    variable initialization_complete 0

set ::debug_audio_count 0

    proc process_buffered_audio {} {
        variable audio_buffer_list

        foreach chunk $audio_buffer_list {
            parse_and_display_result [$::vosk_recognizer process $chunk]
        }
        set audio_buffer_list {}
    }

    proc audio_callback {stream_name timestamp data} {
        variable last_speech_time
        variable audio_buffer_list
        variable initialization_complete
        variable noise_floor

        try {
            set audiolevel [audio::energy $data int16]
            set ::audiolevel $audiolevel

            # Always update energy statistics
            update_energy_stats $audiolevel

            # Show calibration progress during initialization
            if {!$initialization_complete} {
                set progress [expr {[llength $::audio::energy_buffer] * 100 / $::config(initialization_samples)}]
                if {$progress % 10 == 0} {
                    after idle [list partial_text "Calibrating audio environment... ${progress}%"]
                }
                return
            }

            # Use dynamic audio threshold based on noise floor
            set dynamic_threshold [expr {$noise_floor * $::config(audio_threshold_multiplier)}]

            if {$::transcribing} {
                set lookback_frames [expr {int($::config(lookback_seconds) * 10 + 0.5)}]
                lappend audio_buffer_list $data
                set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]

                if {$audiolevel > $dynamic_threshold} {
                    process_buffered_audio
                    set last_speech_time $timestamp
                } else {
                    if {$last_speech_time} {
                        if {$last_speech_time + $::config(silence_seconds) < $timestamp} {
                            process_buffered_audio
                            parse_and_display_result [$::vosk_recognizer final-result]
                            set last_speech_time 0
                        } else {
                            process_buffered_audio
                        }
                    }
                }
            }
        } on error message {
            puts "audio callback: $message"
        }
    }

    proc start_audio_stream {} {
        variable audio_stream

        try {
            set audio_stream [pa::open_stream \
                -device $::config(input_device) \
                -rate $::config(sample_rate) \
                -channels 1 \
                -frames $::config(frames_per_buffer) \
                -format int16 \
                -callback ::audio::audio_callback]

            $audio_stream start

        } on error message {
            puts "start audio stream: $message"
            set audio_stream ""
        }
    }

    proc start_transcription {} {
        variable audio_buffer_list
        variable last_speech_time
        variable speech_energy_sum
        variable speech_energy_count
        variable average_speech_energy
        variable initialization_complete

        # Don't allow transcription until initialized
        if {!$initialization_complete} {
            return false
        }

        set audio_buffer_list {}
        set last_speech_time 0
        set speech_energy_sum 0
        set speech_energy_count 0
        set average_speech_energy 0

        $::vosk_recognizer reset
        textproc_reset

        set ::transcribing 1
        state_save $::transcribing
        return true
    }

    proc stop_transcription {} {
        variable last_speech_time
        variable audio_buffer_list

        set ::transcribing 0
        state_save $::transcribing
        set last_speech_time 0
        set audio_buffer_list {}

        # Vosk recognizer is now persistent, don't clean it up
    }

    proc toggle_transcription {} {
        set ::transcribing [expr {!$::transcribing}]
        state_save $::transcribing
        return $::transcribing
    }

    proc initialize {} {
        if {![::vosk::initialize]} {
            puts "Failed to initialize Vosk recognizer"
            return false
        }

        start_audio_stream

        set ::transcribing [state_load]

        if {$::transcribing} {
            start_transcription
        }

        return true
    }

    proc update_energy_stats {energy} {
        variable energy_buffer
        variable noise_floor
        variable speech_floor
        variable initialization_complete

        # Add to rolling buffer (600 samples = 60 seconds at 10Hz)
        lappend energy_buffer $energy
        if {[llength $energy_buffer] > 600} {
            set energy_buffer [lrange $energy_buffer 1 end]
        }

        # Check for initialization completion
        if {!$initialization_complete && [llength $energy_buffer] >= $::config(initialization_samples)} {
            complete_initialization
        }

        # Recalculate percentiles periodically (every 50 samples)
        if {[llength $energy_buffer] % 50 == 0 && [llength $energy_buffer] >= 50} {
            calculate_percentiles
        }
    }

    proc calculate_percentiles {} {
        variable energy_buffer
        variable noise_floor
        variable speech_floor

        set sorted [lsort -real $energy_buffer]
        set count [llength $sorted]

        if {$count >= 10} {
            set noise_floor [lindex $sorted [expr {int($count * $::config(noise_floor_percentile) / 100.0)}]]
            set new_speech_floor [lindex $sorted [expr {int($count * $::config(speech_floor_percentile) / 100.0)}]]

            # Only update speech_floor if we have a reasonable value
            if {$new_speech_floor > $noise_floor * 1.2} {
                set speech_floor $new_speech_floor
            }
        }
    }

    proc complete_initialization {} {
        variable initialization_complete
        variable noise_floor
        variable speech_floor

        calculate_percentiles

        # Initialize speech_floor if not set by actual speech data
        if {$speech_floor < $noise_floor * 1.5} {
            set speech_floor [expr {$noise_floor * 1.5}]
        }

        set initialization_complete 1
        after idle {partial_text "✓ Audio calibration complete - Ready for transcription"}

        puts "DEBUG: Initialization complete - Noise floor: $noise_floor, Speech floor: $speech_floor"
    }

    proc update_speech_energy {energy} {
        variable speech_energy_sum
        variable speech_energy_count
        variable average_speech_energy

        set speech_energy_sum [expr {$speech_energy_sum + $energy}]
        incr speech_energy_count
        set average_speech_energy [expr {$speech_energy_sum / $speech_energy_count}]

        if {$speech_energy_count % 10 == 0} {
            puts "DEBUG: Good speech energy update - Count: $speech_energy_count, Energy: $energy, Average: $average_speech_energy"
        }
    }

    proc get_dynamic_confidence_threshold {} {
        variable speech_floor
        variable initialization_complete

        # Base threshold from config
        set base_threshold $::config(confidence_threshold)

        # If not initialized yet, use base threshold
        if {!$initialization_complete || $speech_floor == 0} {
            return $base_threshold
        }

        # Define energy range based on speech floor and config
        set min_energy [expr {$speech_floor * $::config(speech_min_multiplier)}]
        set max_energy [expr {$speech_floor * $::config(speech_max_multiplier)}]
        set max_penalty $::config(max_confidence_penalty)

        set current_energy $::audiolevel

        if {$current_energy <= $min_energy} {
            set penalty $max_penalty
        } elseif {$current_energy >= $max_energy} {
            set penalty 0
        } else {
            # Linear interpolation
            set ratio [expr {($current_energy - $min_energy) / ($max_energy - $min_energy)}]
            set penalty [expr {$max_penalty * (1.0 - $ratio)}]
        }

        set final_threshold [expr {$base_threshold + $penalty}]

        puts "DEBUG: Energy: $current_energy, Speech floor: $speech_floor, Range: $min_energy-$max_energy, Penalty: $penalty, Threshold: $final_threshold"

        return $final_threshold
    }

    proc refresh_devices {} {
            set input_device ""
            set input_devices {}
            set preferred $::config(input_device)

            foreach device [pa::list_devices] {
                if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                    set name [dict get $device name]
                    lappend input_devices $name
                    if {$name eq $preferred || [string match "*$preferred*" $name]} {
                        set input_device $name
                        set found_preferred true
                    }
                }
            }

            if {$input_device eq "" && [llength $input_devices] > 0} {
                set ::config(input_device) [lindex $input_devices 0]
            }
            set ::input_device $input_device
            set ::input_devices $input_devices
    }
}
