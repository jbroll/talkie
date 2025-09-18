namespace eval ::audio {
    variable audio_stream ""
    variable audio_buffer_list {}
    variable last_speech_time 0
    variable speech_energy_sum 0
    variable speech_energy_count 0
    variable average_speech_energy 0

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
        variable speech_energy_sum
        variable speech_energy_count
        variable average_speech_energy

        try {
            set lookback_frames [expr {int($::config(lookback_seconds) * 10 + 0.5)}]

            set audiolevel [audio::energy $data int16]

            set ::audiolevel $audiolevel

            # Debug audio levels every 50 callbacks
            if {[incr ::debug_audio_count] % 50 == 0} {
                puts "DEBUG: Audio level: $audiolevel, Threshold: $::config(audio_threshold), Transcribing: $::transcribing"
            }

            if {$::transcribing} {
                lappend audio_buffer_list $data
                set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]

                if { $audiolevel > $::config(audio_threshold) } {
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
        variable average_speech_energy

        # Base threshold from config
        set base_threshold $::config(confidence_threshold)

        # If we don't have speech energy data yet, use base threshold
        if {$average_speech_energy == 0} {
            puts "DEBUG: No speech energy data yet, using base threshold $base_threshold"
            return $base_threshold
        }

        # Current audio energy ratio compared to average speech energy
        set energy_ratio [expr {$::audiolevel / $average_speech_energy}]

        puts "DEBUG: Current energy: $::audiolevel, Average: $average_speech_energy, Ratio: $energy_ratio"

        # Adjust threshold based on configurable energy ratios and boosts
        if {$energy_ratio < $::config(energy_low_threshold)} {
            set threshold [expr {$base_threshold + $::config(confidence_low_boost)}]
            puts "DEBUG: Low energy ratio ($energy_ratio < $::config(energy_low_threshold)), threshold: $threshold"
            return $threshold
        } elseif {$energy_ratio < $::config(energy_med_threshold)} {
            set threshold [expr {$base_threshold + $::config(confidence_med_boost)}]
            puts "DEBUG: Med energy ratio ($energy_ratio < $::config(energy_med_threshold)), threshold: $threshold"
            return $threshold
        } else {
            puts "DEBUG: Good energy ratio ($energy_ratio >= $::config(energy_med_threshold)), threshold: $base_threshold"
            return $base_threshold
        }
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
