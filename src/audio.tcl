proc ::tcl::mathfunc::clip {min val max} {
    expr {($val < $min) ? $min : (($val > $max) ? $max : $val)}
}

namespace eval ::audio {
    # Note: Audio stream is now managed by engine worker thread (engine.tcl)
    # This module handles transcription state and device enumeration
    # Final results go through GEC worker pipeline, partials displayed directly

    # Display partial result from engine (real-time display during speech)
    proc display_partial {text} {
        partial_text $text
    }

    # Display final result from GEC worker (UI notification callback)
    proc display_final {text conf vosk_ms gec_timing} {
        set ::confidence $conf
        after idle [list final_text $text $conf $vosk_ms $gec_timing]
        after idle [partial_text ""]
    }

    proc start_transcription {} {
        ::engine::set_transcribing 1
        ::gec_worker::reset_textproc

        set ::transcribing 1
        state_save $::transcribing
        return true
    }

    proc stop_transcription {} {
        set ::transcribing 0
        state_save $::transcribing

        ::engine::set_transcribing 0
    }

    proc toggle_transcription {} {
        set ::transcribing [expr {!$::transcribing}]
        state_save $::transcribing

        ::engine::set_transcribing $::transcribing
        return $::transcribing
    }

    proc initialize {} {
        # Initialize global health variables (for UI compatibility)
        set ::buffer_health 0
        set ::buffer_overflows 0

        if {![::engine::initialize]} {
            puts "Failed to initialize speech engine"
            return false
        }

        set ::transcribing [state_load]

        if {$::transcribing} {
            start_transcription
        }

        return true
    }

    proc restart_audio_stream {} {
        # Hot-swap audio input device
        refresh_devices
        ::engine::restart_audio $::config(input_device) $::device_sample_rate $::device_frames_per_buffer
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
            catch {set ::input_devices $input_devices}  ;# trace may reference dead widget
            set ::device_info_map $device_info_map
            set ::device_sample_rate $device_sample_rate

            # Calculate frames_per_buffer as ~25ms worth of frames (was 100ms)
            # Smaller chunks = faster speech detection response
            set ::audio_chunk_seconds 0.025
            set ::device_frames_per_buffer [expr {int($device_sample_rate * $::audio_chunk_seconds)}]
    }
}
