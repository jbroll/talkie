proc ::tcl::mathfunc::clip {min val max} {
    expr {($val < $min) ? $min : (($val > $max) ? $max : $val)}
}

namespace eval ::audio {
    variable audio_stream ""
    variable audio_buffer_list {}
    variable this_speech_time 0
    variable last_speech_time 0

    proc process_buffered_audio { } {
        variable audio_buffer_list

        foreach chunk $audio_buffer_list {
            parse_and_display_result [$::vosk_recognizer process $chunk]
        }
        set audio_buffer_list {}
    }

    proc audio_callback {stream_name timestamp data} {
        variable this_speech_time
        variable last_speech_time
        variable audio_buffer_list

        try {
            set audiolevel [audio::energy $data int16]
            set ::audiolevel $audiolevel

            set is_speech [threshold::is_speech $audiolevel $last_speech_time]

            if {$::transcribing} {
                set lookback_frames [expr {int($::config(lookback_seconds) * 10 + 0.5)}]
                lappend audio_buffer_list $data
                set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]

                if { $is_speech } {
                    if { !$last_speech_time } {
                        set this_speech_time $timestamp
                    }
                    set last_speech_time $timestamp
                }
                if { $last_speech_time } {
                    process_buffered_audio

                    if {$last_speech_time + $::config(silence_seconds) < $timestamp} {
                        set result [$::vosk_recognizer final-result]

                        set speech_duration [expr { $last_speech_time - $this_speech_time }]

                        if { $speech_duration > .3 } {
                            parse_and_display_result $result
                        } else {
                            partial_text ""
                            print THRS-SHORTS $speech_duration
                        }
                      
                        set last_speech_time 0
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

    proc parse_and_display_result { result } {
        if { $result eq "" } { return }

        set result_dict [json::json2dict $result]

        if {[dict exists $result_dict partial]} {
            | { dict get $result_dict partial | textproc | partial_text } 
            return
        }

        set text [json-get $result_dict alternatives 0 text]
        set conf [json-get $result_dict alternatives 0 confidence]

        if {$text ne ""} {
            if { [threshold::accept $conf] } {
                set text [textproc $text]
                uinput::type $text
                after idle [final_text $text $conf]
            }
            set ::confidence $conf
        }
        after idle [partial_text ""]
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

        } on error message {
            puts "start audio stream: $message"
            set audio_stream ""
        }
    }

    proc start_transcription {} {
        variable audio_buffer_list
        variable last_speech_time

        if {![threshold::ready]} {
            return false
        }

        set audio_buffer_list {}
        set last_speech_time 0

        $::vosk_recognizer reset
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
        set last_speech_time 0
        set audio_buffer_list {}
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
