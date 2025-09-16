# audio.tcl - Audio management for Talkie

namespace eval ::audio {
    variable current_energy 0.0
    variable audio_stream ""
    variable callback_count 0
    variable audio_buffer_list {}
    variable last_speech_time 0

    proc process_buffered_audio {force_final} {
        variable audio_buffer_list

        set vosk_recognizer [::vosk::get_recognizer]
        if {$vosk_recognizer eq ""} {
            return
        }

        try {
            foreach chunk $audio_buffer_list {
                set result [$vosk_recognizer process $chunk]
                if {$result ne ""} {
                    parse_and_display_result $result
                }
            }

            if {$force_final} {
                set final_result [$vosk_recognizer final-result]
                if {$final_result ne ""} {
                    parse_and_display_result $final_result
                }
            }
        } on error message {
            puts "ERROR $message"
        }

        set audio_buffer_list {}
    }

    proc audio_callback {stream_name timestamp data} {
        variable current_energy
        variable callback_count
        variable last_speech_time
        variable audio_buffer_list

        # Convert seconds to frames locally (each buffer is ~0.1 seconds)
        set lookback_frames [expr {int($::config::config(lookback_seconds) * 10 + 0.5)}]

        incr callback_count

        set current_energy [audio::energy $data int16]

        if {$::transcribing} {
            lappend audio_buffer_list $data
            set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]

            set energy_threshold $::config::config(energy_threshold)
            set is_speech [expr {$current_energy > $energy_threshold}]

            if {$is_speech} {
                process_buffered_audio false
                set last_speech_time $timestamp
            } else {
                if {$last_speech_time} {
                    set silence_duration $::config::config(silence_trailing_duration)
                    if {$last_speech_time + $silence_duration < $timestamp} {
                        process_buffered_audio true
                        set last_speech_time 0
                    } else {
                        process_buffered_audio false
                    }
                }
            }
        }
        after idle ::display::update_energy_display
    }

    proc start_audio_stream {} {
        variable audio_stream

        if {[catch {
            set audio_stream [pa::open_stream \
                -device $::config::config(device) \
                -rate $::config::config(sample_rate) \
                -channels 1 \
                -frames $::config::config(frames_per_buffer) \
                -format int16 \
                -callback ::audio::audio_callback]

            $audio_stream start

        } stream_err]} {
            puts "Audio stream error: $stream_err"
            set audio_stream ""
        }
    }

    proc start_transcription {} {
        variable audio_buffer_list
        variable last_speech_time

        set audio_buffer_list {}
        set last_speech_time 0

        if {[::vosk::initialize]} {
            set ::transcribing true
            return true
        } else {
            return false
        }
    }

    proc stop_transcription {} {
        variable last_speech_time
        variable audio_buffer_list

        set ::transcribing false
        set last_speech_time 0
        set audio_buffer_list {}

        ::vosk::cleanup
    }

    proc toggle_transcription {} {
        set ::transcribing [expr {!$::transcribing}]
        ::config::save_state $::transcribing
        return $::transcribing
    }

    proc get_energy {} {
        variable current_energy
        return $current_energy
    }

    proc initialize {} {
        # Load initial transcribing state from file
        set ::transcribing [::config::load_state]

        start_audio_stream

        # Start transcription if state file says we should be transcribing
        if {$::transcribing} {
            start_transcription
        }
    }
}
