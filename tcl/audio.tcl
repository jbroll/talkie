namespace eval ::audio {
    variable audio_stream ""
    variable audio_buffer_list {}
    variable last_speech_time 0

    proc process_buffered_audio {force_final} {
        variable audio_buffer_list

        foreach chunk $audio_buffer_list {
            parse_and_display_result [$::vosk_recognizer process $chunk]
        }
        set audio_buffer_list {}

        if {$force_final} {
            puts "DEBUG: Calling final-result on recognizer"
            parse_and_display_result [$::vosk_recognizer final-result]
        }
    }

    proc audio_callback {stream_name timestamp data} {
        variable last_speech_time
        variable audio_buffer_list

        try {
            set lookback_frames [expr {int($::config(lookback_seconds) * 10 + 0.5)}]

            set audiolevel [audio::energy $data int16]

            set ::audiolevel $audiolevel

            if {$::transcribing} {
                lappend audio_buffer_list $data
                set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]

                if { $audiolevel > $::config(audio_threshold) } {
                    process_buffered_audio false
                    set last_speech_time $timestamp
                } else {
                    if {$last_speech_time} {
                        if {$last_speech_time + $::config(silence_seconds) < $timestamp} {
                            puts "DEBUG: Silence timeout reached, forcing final result"
                            process_buffered_audio true
                            set last_speech_time 0
                        } else {
                            process_buffered_audio false
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

        set audio_buffer_list {}
        set last_speech_time 0

        $::vosk_recognizer reset

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

    proc refresh_devices {} {
            set input_device ""
            set input_devices {}
            set preferred $::config(input_device)

                print PREFFERED $::config(input_device)

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
