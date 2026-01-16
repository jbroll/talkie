proc ::tcl::mathfunc::clip {min val max} {
    expr {($val < $min) ? $min : (($val > $max) ? $max : $val)}
}

namespace eval ::audio {
    # Note: Audio stream is now managed by engine worker thread (engine.tcl)
    # This module handles result parsing, transcription state, and device enumeration

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

    proc parse_and_display_result { result {vosk_ms 0} } {
        if { $result eq "" } { return }

        set result_dict [json::json2dict $result]

        if {[dict exists $result_dict partial]} {
            | { dict get $result_dict partial | textproc | partial_text }
            return
        }

        # Handle both MBR format (alternatives=0) and N-best format (alternatives>0)
        if {[dict exists $result_dict alternatives]} {
            # N-best format: {"alternatives": [{"text": "...", "confidence": ...}]}
            set text [json-get $result_dict alternatives 0 text]
            set conf [json-get $result_dict alternatives 0 confidence]
        } elseif {[dict exists $result_dict text]} {
            # MBR format: {"text": "...", "result": [{"word":..., "conf":...}, ...]}
            set text [dict get $result_dict text]
            # Calculate average confidence from per-word results
            if {[dict exists $result_dict result]} {
                set words [dict get $result_dict result]
                set total_conf 0.0
                set word_count 0
                foreach word_info $words {
                    if {[dict exists $word_info conf]} {
                        set total_conf [expr {$total_conf + [dict get $word_info conf]}]
                        incr word_count
                    }
                }
                if {$word_count > 0} {
                    set conf [expr {($total_conf / $word_count) * 100}]
                } else {
                    set conf 100
                }
            } else {
                set conf 100
            }
        } else {
            return
        }

        if { [lsearch -exact $::killwords $text] < 0 } {
            if { [threshold::accept $conf] } {
                # GEC processing (homophone correction + punct/caps)
                set gec_timing {}
                if {[info exists ::gec_enabled] && $::gec_enabled} {
                    set text [::gec::process $text]
                    set gec_timing [::gec::last_timing]
                }
                # Then textproc handles spacing, voice commands (period->.), etc.
                set text [textproc $text]
                ::output::type_async $text
                after idle [list final_text $text $conf $vosk_ms $gec_timing]
            }
            set ::confidence $conf
        }
        after idle [partial_text ""]
    }

    proc start_transcription {} {
        ::engine::set_transcribing 1
        textproc_reset

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
            catch {set ::input_devices $input_devices}  ;# trace may reference dead widget
            set ::device_info_map $device_info_map
            set ::device_sample_rate $device_sample_rate

            # Calculate frames_per_buffer as ~25ms worth of frames (was 100ms)
            # Smaller chunks = faster speech detection response
            set ::audio_chunk_seconds 0.025
            set ::device_frames_per_buffer [expr {int($device_sample_rate * $::audio_chunk_seconds)}]
    }
}
