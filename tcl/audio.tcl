# audio.tcl - Audio management for Talkie

namespace eval ::audio {
    variable transcribing false
    variable current_energy 0.0
    variable audio_stream ""
    variable callback_count 0
    variable audio_buffer_list {}
    variable last_speech_time 0

    proc add_to_buffer {data} {
        variable audio_buffer_list

        # Add new data to end of list
        lappend audio_buffer_list $data

        # Keep only the last N frames using end-based indexing
        set lookback_frames [::config::get lookback_frames]
        if {[llength $audio_buffer_list] > $lookback_frames} {
            set audio_buffer_list [lrange $audio_buffer_list end-[expr {$lookback_frames-1}] end]
        }
    }

    proc process_buffered_audio {force_final} {
        variable audio_buffer_list

        set vosk_recognizer [::vosk::get_recognizer]
        if {$vosk_recognizer eq ""} {
            return
        }

        foreach chunk $audio_buffer_list {
            if {[catch {
                set result [$vosk_recognizer process $chunk]
                if {$result ne ""} {
                    ::vosk::parse_and_display_result $result
                }
            } err]} {
                puts "VOSK-CHUNK-ERROR: $err"
            }
        }

        if {$force_final} {
            if {[catch {
                set final_result [$vosk_recognizer final-result]
                if {$final_result ne ""} {
                    ::vosk::parse_and_display_result $final_result
                }
            } err]} {
                puts "VOSK-FINAL-ERROR: $err"
            }
        }

        set audio_buffer_list {}
    }

    proc audio_callback {stream_name timestamp data} {
        variable transcribing
        variable current_energy
        variable callback_count
        variable last_speech_time
        variable audio_buffer_list

        incr callback_count

        set current_energy [audio::energy $data int16]

        if {$transcribing} {
            add_to_buffer $data

            set energy_threshold [::config::get energy_threshold]
            set is_speech [expr {$current_energy > $energy_threshold}]

            if {$is_speech} {
                process_buffered_audio false
                set last_speech_time $timestamp
            } else {
                if {$last_speech_time} {
                    set silence_duration [::config::get silence_trailing_duration]
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
                -device [::config::get device] \
                -rate [::config::get sample_rate] \
                -channels 1 \
                -frames [::config::get frames_per_buffer] \
                -format int16 \
                -callback ::audio::audio_callback]

            $audio_stream start

        } stream_err]} {
            puts "Audio stream error: $stream_err"
            set audio_stream ""
        }
    }

    proc start_transcription {} {
        variable transcribing
        variable audio_buffer_list
        variable last_speech_time

        set audio_buffer_list {}
        set last_speech_time 0

        if {[::vosk::initialize]} {
            set transcribing true
            return true
        } else {
            return false
        }
    }

    proc stop_transcription {} {
        variable transcribing
        variable last_speech_time
        variable audio_buffer_list

        set transcribing false
        set last_speech_time 0
        set audio_buffer_list {}

        ::vosk::cleanup
    }

    proc toggle_transcription {} {
        variable transcribing

        set transcribing [expr {!$transcribing}]

        if {$transcribing} {
            start_transcription
        } else {
            stop_transcription
        }

        return $transcribing
    }

    proc get_energy {} {
        variable current_energy
        return $current_energy
    }

    proc is_transcribing {} {
        variable transcribing
        return $transcribing
    }

    proc initialize {} {
        start_audio_stream
    }
}