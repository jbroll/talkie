#!/usr/bin/env tclsh
# talkie.tcl - Tcl version matching Python interface exactly

package require Tk

# Try to load ttk, but don't fail if not available
if {[catch {package require ttk}]} {
    # Create a simple combobox replacement if ttk is not available
    namespace eval ttk {}
    proc ttk::combobox {path args} {
        # Parse args to extract non-entry options
        set entry_args {}
        set values {}

        foreach {opt val} $args {
            if {$opt eq "-values"} {
                set values $val
            } else {
                lappend entry_args $opt $val
            }
        }

        # Create entry widget
        eval [list entry $path] $entry_args

        # Store values as a property
        if {$values ne ""} {
            $path configure -validate none
        }

        # Add config method to handle -values
        rename $path ${path}_orig
        proc $path {args} [subst -nocommands {
            if {[llength \$args] >= 2 && [lindex \$args 0] eq "config" && [lindex \$args 1] eq "-values"} {
                # Handle config -values
                return
            }
            eval [list ${path}_orig] \$args
        }]

        return $path
    }
}

# Setup paths for existing packages
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib pa]
lappend auto_path [file join $script_dir vosk lib vosk]
lappend auto_path [file join $script_dir audio lib audio]
set ::env(TCLLIBPATH) "$::env(HOME)/.local/lib"

# Test mode detection
set test_mode false
if {[lsearch $argv "-test"] >= 0} {
    set test_mode true
    puts "=== TALKIE TEST MODE ENABLED ==="
    puts "This will show detailed pipeline instrumentation"
}

# Load packages
puts "Talkie Tcl Edition"
puts "=================="
puts "\nInitializing components..."

if {[catch {
    package require pa
    pa::init
    Pa_Init
    puts "✓ PortAudio loaded and initialized"
} err]} {
    puts "✗ PortAudio error: $err"
    exit 1
}

if {[catch {
    package require vosk
    if {[info commands Vosk_Init] ne ""} {
        Vosk_Init
    }
    # Check what commands are available and set log level
    if {[info commands vosk::set_log_level] ne ""} {
        vosk::set_log_level -1
    }
    puts "✓ Vosk loaded and initialized"
} err]} {
    puts "✗ Vosk error: $err"
    exit 1
}

if {[catch {
    package require audio
    puts "✓ Audio processing loaded"
} err]} {
    puts "✗ Audio processing error: $err"
    exit 1
}

# Configuration
array set config {
    sample_rate 44100
    frames_per_buffer 4410
    energy_threshold 5.0
    confidence_threshold 280.0
    window_x 100
    window_y 100
    device "pulse"
    model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
    silence_trailing_duration 0.5
    lookback_duration 1.0
    lookback_frames 10
    vosk_max_alternatives 0
    vosk_beam 20
    vosk_lattice_beam 8
}

# Initialize lookback_frames based on lookback_duration
set config(lookback_frames) [expr {int($config(lookback_duration) * 10 + 0.5)}]

# Config file path - XDG-compliant like Python version
proc get_config_file_path {} {
    if {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""} {
        set config_dir $::env(XDG_CONFIG_HOME)
        file mkdir $config_dir
        return [file join $config_dir talkie.conf]
    } else {
        return [file join $::env(HOME) .talkie.conf]
    }
}

# Load configuration from JSON file
proc load_config {} {
    global config test_mode

    set config_file [get_config_file_path]

    if {[file exists $config_file]} {
        if {[catch {
            set fp [open $config_file r]
            set json_data [read $fp]
            close $fp

            # Parse JSON and update config array
            set config_dict [json::decode $json_data]
            dict for {key value} $config_dict {
                set config($key) $value
            }

            if {$test_mode} {
                puts "CONFIG: Loaded from $config_file"
            }
        } err]} {
            if {$test_mode} {
                puts "CONFIG: Error loading config: $err"
            }
        }
    } else {
        # Create default config file
        save_config
        if {$test_mode} {
            puts "CONFIG: Created default config at $config_file"
        }
    }

    # Recalculate lookback_frames based on loaded lookback_duration
    set config(lookback_frames) [expr {int($config(lookback_duration) * 10 + 0.5)}]
}

# Save configuration to JSON file
proc save_config {} {
    global config test_mode

    set config_file [get_config_file_path]

    if {[catch {
        # Convert config array to JSON
        set json_data "{\n"
        set first true
        foreach key [lsort [array names config]] {
            if {!$first} {
                append json_data ",\n"
            }
            set first false

            # Format value based on type
            set value $config($key)
            if {[string is double -strict $value]} {
                append json_data "  \"$key\": $value"
            } elseif {[string is integer -strict $value]} {
                append json_data "  \"$key\": $value"
            } elseif {[string is boolean -strict $value]} {
                append json_data "  \"$key\": [expr {$value ? "true" : "false"}]"
            } else {
                # String value - escape quotes
                set escaped_value [string map {\" \\\"} $value]
                append json_data "  \"$key\": \"$escaped_value\""
            }
        }
        append json_data "\n}"

        set fp [open $config_file w]
        puts $fp $json_data
        close $fp

        if {$test_mode} {
            puts "CONFIG: Saved to $config_file"
        }
    } err]} {
        if {$test_mode} {
            puts "CONFIG: Error saving config: $err"
        }
    }
}

# Update a single config parameter and save to file
proc update_config_param {key value} {
    global config
    set config($key) $value
    save_config
}

# Global state
set transcribing false
set current_energy 0.0
set current_confidence 0.0
set audio_stream ""
set vosk_model ""
set vosk_recognizer ""
set callback_count 0
set last_update_time 0
set current_view "text"

# Lookback buffering state
set audio_buffer_list {}
set speech_active false
set silence_start_time 0
set last_speech_time 0

# UI variables
array set ui {}

# Setup main window - matching Python exactly
wm title . "Talkie"
wm geometry . 800x500+$config(window_x)+$config(window_y)
wm minsize . 800 400

# Button row frame - EXACTLY matching Python layout
set button_frame [frame .buttons]
pack $button_frame -fill x -pady 10

# Main transcription toggle button (flush left)
set ui(toggle_btn) [button $button_frame.toggle \
    -text "Start Transcription" \
    -command toggle_transcription \
    -activebackground "indianred"]
pack $ui(toggle_btn) -side left -pady 0

# View switching buttons (left-center)
set ui(controls_btn) [button $button_frame.controls \
    -text "Controls" \
    -command show_controls_view]
pack $ui(controls_btn) -side left -padx 5 -pady 0

set ui(text_btn) [button $button_frame.text \
    -text "Text" \
    -command show_text_view \
    -relief sunken]
pack $ui(text_btn) -side left -pady 0

# Audio energy display (center-left) - styled like Python
set ui(energy_label) [label $button_frame.energy \
    -text "Audio: 0" \
    -relief raised -bd 2 \
    -padx 10 -pady 5 \
    -font [list Arial 10]]
pack $ui(energy_label) -side left -expand true -padx {10 5} -pady 0

# Confidence display (center-right) - styled like Python
set ui(confidence_label) [label $button_frame.confidence \
    -text "Conf: --" \
    -relief raised -bd 2 \
    -padx 10 -pady 5 \
    -font [list Arial 10]]
pack $ui(confidence_label) -side left -expand true -padx {5 10} -pady 0

# Quit button (flush right)
set ui(quit_btn) [button $button_frame.quit \
    -text "Quit" \
    -command quit_app]
pack $ui(quit_btn) -side right -pady 0

# Content frame for switchable panes
set ui(content_frame) [frame .content]
pack $ui(content_frame) -fill both -expand true -padx 10 -pady 5

# Initialize lookback buffer
proc init_lookback_buffer {} {
    global audio_buffer_list
    set audio_buffer_list {}
}

# Add data to lookback buffer and maintain size limit
proc add_to_buffer {data} {
    global audio_buffer_list config

    # Add new data to end of list
    lappend audio_buffer_list $data

    # Keep only the last N frames using end-based indexing
    if {[llength $audio_buffer_list] > $config(lookback_frames)} {
        set audio_buffer_list [lrange $audio_buffer_list end-[expr {$config(lookback_frames)-1}] end]
    }
}

# Process buffered audio chunks directly through Vosk (force_final only when silence timeout expires)
proc process_buffered_audio {force_final} {
    global audio_buffer_list vosk_recognizer test_mode

    if {$vosk_recognizer eq ""} {
        return
    }

    if {$test_mode} {
        puts "VOSK-PROCESS: Processing [llength $audio_buffer_list] buffered chunks directly"
    }

    # Process each chunk through Vosk
    foreach chunk $audio_buffer_list {
        if {[catch {
            set result [$vosk_recognizer process $chunk]
            if {$result ne ""} {
                parse_and_display_result $result false
            }
        } err]} {
            if {$test_mode} {
                puts "VOSK-CHUNK-ERROR: $err"
            }
        }
    }

    # Only get final result if forced (when silence timeout expires)
    if {$force_final} {
        if {[catch {
            set final_result [$vosk_recognizer final-result]
            if {$final_result ne ""} {
                parse_and_display_result $final_result true
            }
        } err]} {
            if {$test_mode} {
                puts "VOSK-FINAL-ERROR: $err"
            }
        }
    }

    # Clear the buffer
    set audio_buffer_list {}
}

# Parse and display Vosk recognition result
proc parse_and_display_result {result is_final} {
    global current_confidence config test_mode

    if {$test_mode && $result ne ""} {
        puts "VOSK-RAW-JSON: $result"
    }

    if {[catch {
        set result_dict [json::decode $result]
        if {[dict exists $result_dict text] && [dict get $result_dict text] ne ""} {
            set text [dict get $result_dict text]
            set conf 0.0
            if {[dict exists $result_dict conf]} {
                set conf [expr {[dict get $result_dict conf] * 1000}]
            }
            set current_confidence $conf

            # Always display text for now - confidence filtering can be re-enabled later
            after idle [list display_final_text $text $conf]

            if {$test_mode} {
                set type [expr {$is_final ? "FINAL" : "PARTIAL"}]
                puts "VOSK-$type: text='$text', confidence=$conf, threshold=$config(confidence_threshold)"
            }
        }
    } parse_err]} {
        if {$test_mode} {
            puts "VOSK-PARSE-ERROR: $parse_err"
        }
    }
}

# Audio callback function - handles real PA buffer data with lookback buffering
proc audio_callback {stream_name timestamp data} {
    global vosk_recognizer current_energy current_confidence config test_mode callback_count transcribing
    global speech_active silence_start_time last_speech_time audio_buffer_list

    incr callback_count

    # TEST MODE: Show PA buffer information
    if {$test_mode && $callback_count % 20 == 1} {
        puts "PA-CALLBACK #$callback_count: stream=$stream_name, timestamp=[format "%.3f" $timestamp], data_size=[string length $data] bytes"
    }

    set current_energy [audio::energy $data int16]
    if {$test_mode && $callback_count % 20 == 1} {
        puts "ENERGY-CALC: Using C function audio::energy, result=$current_energy"
    }

    # Always update UI with current energy
    after idle update_energy_display

    # Only process with voice activity detection if transcription is enabled
    if {$transcribing && $vosk_recognizer ne ""} {
        # Add current data to circular buffer for lookback
        add_to_buffer $data

        set current_time $timestamp
        set is_speech [expr {$current_energy > $config(energy_threshold)}]

        if {$test_mode && $callback_count % 20 == 1} {
            puts "VAD: energy=$current_energy, threshold=$config(energy_threshold), is_speech=$is_speech, speech_active=$speech_active"
        }

        # Voice activity detection logic
        if {$is_speech} {
            # Speech detected
            if {!$speech_active} {
                # Speech just started - start collecting from lookback buffer
                set speech_active true

                if {$test_mode} {
                    puts "SPEECH-START: Using [llength $audio_buffer_list] buffered chunks as lookback"
                }
            }

            set last_speech_time $current_time

        } else {
            # No speech detected
            if {$speech_active} {
                # We were in speech, now checking for silence duration
                if {$silence_start_time == 0} {
                    set silence_start_time $current_time
                    if {$test_mode} {
                        puts "SILENCE-START: Beginning silence trailing at $current_time"
                    }
                }

                # Check if silence duration exceeded
                set silence_duration [expr {$current_time - $silence_start_time}]
                if {$silence_duration >= $config(silence_trailing_duration)} {
                    # End of speech - process buffered audio and force final result
                    if {$test_mode} {
                        puts "SPEECH-END: Processing [llength $audio_buffer_list] chunks after ${silence_duration}s silence"
                    }

                    # Process all buffered chunks and force final result from Vosk
                    process_buffered_audio true

                    # Reset state
                    set speech_active false
                    set silence_start_time 0
                }
            }
        }
    }
}


# Setup switchable panes - matching Python exactly
proc setup_switchable_panes {} {
    global ui

    # Controls pane with scrolling
    set ui(controls_pane) [frame $ui(content_frame).controls]
    setup_controls_pane

    # Text pane
    set ui(text_pane) [frame $ui(content_frame).text]
    setup_text_pane

    # Note: Text view will be shown after all UI setup is complete
}

# Setup controls pane with scrolling like Python
proc setup_controls_pane {} {
    global ui config

    # Create canvas and scrollbar for scrolling
    set ui(controls_canvas) [canvas $ui(controls_pane).canvas]
    set ui(controls_scrollbar) [scrollbar $ui(controls_pane).scroll \
        -orient vertical -command "$ui(controls_canvas) yview"]

    # Create scrollable frame inside canvas
    set ui(scrollable_controls_frame) [frame $ui(controls_canvas).scrollable]

    # Configure canvas
    $ui(controls_canvas) configure -yscrollcommand "$ui(controls_scrollbar) set"
    $ui(controls_canvas) create window 0 0 -window $ui(scrollable_controls_frame) -anchor nw

    # Pack canvas and scrollbar
    pack $ui(controls_canvas) -side left -fill both -expand true
    pack $ui(controls_scrollbar) -side right -fill y

    # Bind mousewheel and configure events
    bind $ui(scrollable_controls_frame) <Configure> {
        $ui(controls_canvas) configure -scrollregion [$ui(controls_canvas) bbox all]
    }

    # Mouse wheel bindings
    bind $ui(controls_canvas) <MouseWheel> {
        $ui(controls_canvas) yview scroll [expr {-1 * (%D / 120)}] units
    }
    bind $ui(controls_canvas) <Button-4> {
        $ui(controls_canvas) yview scroll -1 units
    }
    bind $ui(controls_canvas) <Button-5> {
        $ui(controls_canvas) yview scroll 1 units
    }

    # Setup controls within scrollable frame
    setup_controls_content
}

# Setup controls content - matching Python layout
proc setup_controls_content {} {
    global ui config

    set controls_container [frame $ui(scrollable_controls_frame).container]
    pack $controls_container -pady 10 -padx 20 -fill x

    # Device selection row - matching Python exactly
    set device_frame [frame $controls_container.device]
    pack $device_frame -fill x -pady 2

    label $device_frame.label -text "Audio Device:" -width 20 -anchor w
    pack $device_frame.label -side left

    set device_control_frame [frame $device_frame.control]
    pack $device_control_frame -side right -fill x -expand true

    # Create a proper dropdown using menubutton
    set ui(device_var) ""
    set ui(device_menubutton) [menubutton $device_control_frame.mb \
        -textvariable ui(device_var) \
        -indicatoron 1 \
        -relief raised \
        -bd 2 \
        -highlightthickness 2 \
        -anchor w]
    pack $ui(device_menubutton) -side left -fill x -expand true

    set ui(device_menu) [menu $ui(device_menubutton).menu -tearoff 0]
    $ui(device_menubutton) config -menu $ui(device_menu)

    button $device_control_frame.refresh -text "Refresh" -command refresh_devices
    pack $ui(device_menubutton) -side left -fill x -expand true -padx {0 5}
    pack $device_control_frame.refresh -side right

    # Energy threshold row
    set energy_frame [frame $controls_container.energy]
    pack $energy_frame -fill x -pady 2

    label $energy_frame.label -text "Energy Threshold:" -width 20 -anchor w
    pack $energy_frame.label -side left

    set energy_control_frame [frame $energy_frame.control]
    pack $energy_control_frame -side right -fill x -expand true

    set ui(energy_scale) [scale $energy_control_frame.scale \
        -from 10 -to 100 -resolution 5 -orient horizontal \
        -command energy_changed]
    pack $ui(energy_scale) -fill x -expand true
    $ui(energy_scale) set $config(energy_threshold)

    # Silence trailing duration row
    set silence_frame [frame $controls_container.silence]
    pack $silence_frame -fill x -pady 2

    label $silence_frame.label -text "Silence Duration (s):" -width 20 -anchor w
    pack $silence_frame.label -side left

    set silence_control_frame [frame $silence_frame.control]
    pack $silence_control_frame -side right -fill x -expand true

    set ui(silence_scale) [scale $silence_control_frame.scale \
        -from 0.1 -to 2.0 -resolution 0.1 -orient horizontal \
        -command silence_changed]
    pack $ui(silence_scale) -fill x -expand true
    $ui(silence_scale) set $config(silence_trailing_duration)

    # Confidence threshold row
    set confidence_frame [frame $controls_container.confidence]
    pack $confidence_frame -fill x -pady 2

    label $confidence_frame.label -text "Confidence Threshold:" -width 20 -anchor w
    pack $confidence_frame.label -side left

    set confidence_control_frame [frame $confidence_frame.control]
    pack $confidence_control_frame -side right -fill x -expand true

    set ui(confidence_scale) [scale $confidence_control_frame.scale \
        -from 200 -to 400 -resolution 10 -orient horizontal \
        -command confidence_changed]
    pack $ui(confidence_scale) -fill x -expand true
    $ui(confidence_scale) set $config(confidence_threshold)

    # Vosk beam row
    set beam_frame [frame $controls_container.beam]
    pack $beam_frame -fill x -pady 2

    label $beam_frame.label -text "Vosk Beam:" -width 20 -anchor w
    pack $beam_frame.label -side left

    set beam_control_frame [frame $beam_frame.control]
    pack $beam_control_frame -side right -fill x -expand true

    set ui(beam_scale) [scale $beam_control_frame.scale \
        -from 5 -to 50 -resolution 1 -orient horizontal \
        -command beam_changed]
    pack $ui(beam_scale) -fill x -expand true
    $ui(beam_scale) set $config(vosk_beam)

    # Vosk lattice beam row
    set lattice_frame [frame $controls_container.lattice]
    pack $lattice_frame -fill x -pady 2

    label $lattice_frame.label -text "Lattice Beam:" -width 20 -anchor w
    pack $lattice_frame.label -side left

    set lattice_control_frame [frame $lattice_frame.control]
    pack $lattice_control_frame -side right -fill x -expand true

    set ui(lattice_scale) [scale $lattice_control_frame.scale \
        -from 1 -to 20 -resolution 1 -orient horizontal \
        -command lattice_changed]
    pack $ui(lattice_scale) -fill x -expand true
    $ui(lattice_scale) set $config(vosk_lattice_beam)

    # Vosk alternatives row
    set alternatives_frame [frame $controls_container.alternatives]
    pack $alternatives_frame -fill x -pady 2

    label $alternatives_frame.label -text "Max Alternatives:" -width 20 -anchor w
    pack $alternatives_frame.label -side left

    set alternatives_control_frame [frame $alternatives_frame.control]
    pack $alternatives_control_frame -side right -fill x -expand true

    set ui(alternatives_scale) [scale $alternatives_control_frame.scale \
        -from 0 -to 5 -resolution 1 -orient horizontal \
        -command alternatives_changed]
    pack $ui(alternatives_scale) -fill x -expand true
    $ui(alternatives_scale) set $config(vosk_max_alternatives)

    # Lookback duration row
    set lookback_frame [frame $controls_container.lookback]
    pack $lookback_frame -fill x -pady 2

    label $lookback_frame.label -text "Lookback Duration (s):" -width 20 -anchor w
    pack $lookback_frame.label -side left

    set lookback_control_frame [frame $lookback_frame.control]
    pack $lookback_control_frame -side right -fill x -expand true

    set ui(lookback_scale) [scale $lookback_control_frame.scale \
        -from 0.1 -to 3.0 -resolution 0.1 -orient horizontal \
        -command lookback_changed]
    pack $ui(lookback_scale) -fill x -expand true
    $ui(lookback_scale) set $config(lookback_duration)
}

# Setup text pane - matching Python exactly
proc setup_text_pane {} {
    global ui

    # Main text frame
    set text_frame [frame $ui(text_pane).textframe]
    pack $text_frame -pady 10 -fill both -expand true

    # Final results history (top, large) - rolling buffer without scrollbar
    set ui(final_text) [text $text_frame.final -wrap word -width 80 -height 12]
    pack $ui(final_text) -fill both -expand true -pady {0 5}

    # Configure tags for final results
    $ui(final_text) tag configure "final" -foreground "black"
    $ui(final_text) tag configure "timestamp" -foreground "gray" -font [list Arial 8]

    # Initialize rolling buffer management
    set ui(max_lines) 15
    set ui(current_lines) 0

    # Current partial text (bottom, smaller) - matching Python
    set partial_frame [frame $text_frame.partial_frame]
    pack $partial_frame -fill x -pady {5 0}

    set ui(partial_text) [text $partial_frame.text -wrap word -width 80 -height 3]
    pack $ui(partial_text) -fill both -expand true

    # Configure tags for partial results
    $ui(partial_text) tag configure "sent" -foreground "gray"
}

# View switching functions - matching Python exactly
proc show_controls_view {} {
    global ui current_view

    if {$current_view eq "controls"} return

    # Hide text pane, show controls pane
    if {[winfo exists $ui(text_pane)]} {
        pack forget $ui(text_pane)
    }
    pack $ui(controls_pane) -fill both -expand true

    # Update button states
    $ui(controls_btn) config -relief sunken
    $ui(text_btn) config -relief raised

    set current_view "controls"
}

proc show_text_view {} {
    global ui current_view

    if {$current_view eq "text"} return

    # Hide controls pane, show text pane
    if {[winfo exists $ui(controls_pane)]} {
        pack forget $ui(controls_pane)
    }
    pack $ui(text_pane) -fill both -expand true

    # Update button states (with existence check)
    if {[info exists ui(text_btn)] && [winfo exists $ui(text_btn)]} {
        $ui(text_btn) config -relief sunken
    }
    if {[info exists ui(controls_btn)] && [winfo exists $ui(controls_btn)]} {
        $ui(controls_btn) config -relief raised
    }

    set current_view "text"
}

# Event handlers
proc toggle_transcription {} {
    global transcribing ui

    set transcribing [expr {!$transcribing}]

    if {$transcribing} {
        $ui(toggle_btn) config -text "Stop Transcription" -bg "#f44336" -fg white
        start_transcription
    } else {
        $ui(toggle_btn) config -text "Start Transcription" -bg "#4CAF50" -fg white
        stop_transcription
    }
}

# Update displays
proc update_energy_display {} {
    global current_energy current_confidence ui test_mode last_update_time

    # TEST MODE: Track UI update timing
    if {$test_mode} {
        set current_time [clock milliseconds]
        if {$last_update_time > 0} {
            set time_diff [expr {$current_time - $last_update_time}]
            if {$time_diff > 500} {
                puts "UI-UPDATE: Energy display update after ${time_diff}ms, energy=$current_energy, confidence=$current_confidence"
            }
        }
        set last_update_time $current_time
    }

    # Update energy display
    $ui(energy_label) config -text [format "Audio: %.1f" $current_energy]

    # Color code energy level
    if {$current_energy > 50.0} {
        $ui(energy_label) config -bg "#4CAF50" -fg white
    } elseif {$current_energy > 20.0} {
        $ui(energy_label) config -bg "#FF9800" -fg white
    } elseif {$current_energy > 0.0} {
        $ui(energy_label) config -bg "#2196F3" -fg white
    } else {
        $ui(energy_label) config -bg "#f44336" -fg white
    }

    # Update confidence display
    $ui(confidence_label) config -text [format "Conf: %.0f" $current_confidence]

    # Color code confidence
    if {$current_confidence >= 320} {
        $ui(confidence_label) config -bg "#4CAF50" -fg white
    } elseif {$current_confidence >= 280} {
        $ui(confidence_label) config -bg "#FF9800" -fg white
    } else {
        $ui(confidence_label) config -bg "#f44336" -fg white
    }

    if {$test_mode && $current_energy > 0} {
        puts "UI-ENERGY: Updated energy=$current_energy, confidence=$current_confidence"
    }
}

# Start UI update timer and background energy monitoring
proc start_ui_updates {} {
    update_energy_display
    after 100 start_ui_updates
}

# Audio stream management - always running for energy monitoring
proc start_audio_stream {} {
    global config audio_stream test_mode

    if {[catch {
        set audio_stream [pa::open_stream \
            -device $config(device) \
            -rate $config(sample_rate) \
            -channels 1 \
            -frames 4410 \
            -format int16 \
            -callback audio_callback]

        $audio_stream start

        if {$test_mode} {
            puts "AUDIO-STREAM: Started audio capture for energy monitoring"
        }
    } stream_err]} {
        puts "Audio stream error: $stream_err"
        set audio_stream ""
    }
}


# Display functions
proc display_final_text {text confidence} {
    global ui test_mode

    if {$test_mode} {
        puts "DISPLAY-TEXT: Called with text='$text', confidence=$confidence"
    }

    if {![info exists ui(final_text)]} {
        if {$test_mode} {
            puts "DISPLAY-TEXT: ui(final_text) does not exist!"
        }
        return
    }

    set timestamp [clock format [clock seconds] -format "%H:%M:%S"]

    $ui(final_text) config -state normal

    # Check if we need to remove old lines (rolling buffer)
    if {$ui(current_lines) >= $ui(max_lines)} {
        # Remove the first line to make room
        $ui(final_text) delete 1.0 2.0
    } else {
        incr ui(current_lines)
    }

    # Add new line at the end
    $ui(final_text) insert end "$timestamp " "timestamp"
    $ui(final_text) insert end "([format "%.0f" $confidence]): $text\n" "final"

    # Always keep the view at the bottom (most recent text)
    $ui(final_text) see end
    $ui(final_text) config -state disabled
}

proc update_partial_text {partial_result} {
    global ui

    if {![info exists ui(partial_text)]} return

    # Parse partial result JSON
    if {[catch {
        set result_dict [json::decode $partial_result]
        if {[dict exists $result_dict partial]} {
            set partial [dict get $result_dict partial]
            $ui(partial_text) config -state normal
            $ui(partial_text) delete 1.0 end
            $ui(partial_text) insert end $partial
            $ui(partial_text) config -state disabled
        }
    }]} {
        # Ignore parse errors for partial results
    }
}

# Control change handlers
proc device_changed {} {
    global ui config
    set config(device) $ui(device_var)
}

proc device_selected {device} {
    global ui config
    set config(device) $device
    set ui(device_var) $device
}

proc energy_changed {value} {
    update_config_param energy_threshold $value
}

proc silence_changed {value} {
    update_config_param silence_trailing_duration $value
}

proc confidence_changed {value} {
    update_config_param confidence_threshold $value
}

proc beam_changed {value} {
    update_config_param vosk_beam $value
}

proc lattice_changed {value} {
    update_config_param vosk_lattice_beam $value
}

proc alternatives_changed {value} {
    update_config_param vosk_max_alternatives $value
}

proc lookback_changed {value} {
    global config
    update_config_param lookback_duration $value
    # Convert seconds to frames: each buffer is ~0.1 seconds (4410 frames at 44100 Hz)
    # So frames = duration * 10, rounded to nearest integer
    set config(lookback_frames) [expr {int($value * 10 + 0.5)}]
    update_config_param lookback_frames $config(lookback_frames)
}

# Audio device detection
proc refresh_devices {} {
    global ui config

    if {[catch {
        set devices [pa::list_devices]
        set input_devices {}
        set default_found false

        foreach device $devices {
            if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                set device_name [dict get $device name]
                lappend input_devices $device_name

                # Check for pulse device
                if {$device_name eq "pulse" || [string match "*pulse*" $device_name]} {
                    set config(device) $device_name
                    set default_found true
                }
            }
        }

        # Update UI if it exists
        if {[info exists ui(device_menu)]} {
            # Clear and populate dropdown menu
            $ui(device_menu) delete 0 end
            foreach device $input_devices {
                $ui(device_menu) add command -label $device -command [list device_selected $device]
            }

            # Set current device
            if {$default_found} {
                set ui(device_var) $config(device)
            } elseif {[llength $input_devices] > 0} {
                # If no pulse device found, use first available
                set config(device) [lindex $input_devices 0]
                set ui(device_var) $config(device)
            }
        }
    } err]} {
        puts "Error refreshing devices: $err"
    }
}

# Transcription functions
proc start_transcription {} {
    global config vosk_model vosk_recognizer test_mode transcribing
    global speech_active silence_start_time last_speech_time audio_buffer_list

    # Initialize lookback buffer
    init_lookback_buffer

    # Reset voice activity detection state
    set speech_active false
    set silence_start_time 0
    set last_speech_time 0

    # Initialize Vosk
    if {[catch {
        if {[info commands vosk::set_log_level] ne ""} {
            vosk::set_log_level -1
        }

        if {[file exists $config(model_path)]} {
            set vosk_model [vosk::load_model -path $config(model_path)]
            set vosk_recognizer [$vosk_model create_recognizer -rate $config(sample_rate)]

            if {$test_mode} {
                puts "VOSK-INIT: Model loaded from $config(model_path), recognizer created"
            }
        } else {
            error "Vosk model not found at $config(model_path)"
        }
    } vosk_err]} {
        puts "Vosk initialization error: $vosk_err"
        return
    }

    # Enable transcription - audio stream is already running
    set transcribing true

    if {$test_mode} {
        puts "TRANSCRIPTION-START: Vosk ready, transcribing enabled, audio callbacks will process with Vosk"
    }
}

proc stop_transcription {} {
    global vosk_recognizer vosk_model test_mode transcribing
    global speech_active silence_start_time last_speech_time audio_buffer_list

    # Disable transcription - audio stream keeps running for energy monitoring
    set transcribing false

    # Reset voice activity detection state
    set speech_active false
    set silence_start_time 0
    set last_speech_time 0
    set audio_buffer_list {}

    # Clean up Vosk resources
    set vosk_recognizer ""
    set vosk_model ""

    if {$test_mode} {
        puts "TRANSCRIPTION-STOP: Vosk disabled, audio stream continues for energy monitoring"
    }
}

# Simple JSON parser
namespace eval json {
    proc decode {json_string} {
        set json_string [string trim $json_string]
        if {[string index $json_string 0] ne "\{" || [string index $json_string end] ne "\}"} {
            error "Invalid JSON format"
        }

        set content [string range $json_string 1 end-1]
        set result {}

        set pairs [split $content ","]
        foreach pair $pairs {
            set pair [string trim $pair]
            if {[regexp {"([^"]+)"\s*:\s*"([^"]*)"} $pair -> key value]} {
                dict set result $key $value
            } elseif {[regexp {"([^"]+)"\s*:\s*([0-9.-]+)} $pair -> key value]} {
                dict set result $key $value
            }
        }

        return $result
    }
}

# Quit function
proc quit_app {} {
    global transcribing

    if {$transcribing} {
        stop_transcription
    }

    if {[catch {pa::terminate}]} {
        # Ignore cleanup errors
    }

    exit
}

# Initialize application
load_config
setup_switchable_panes
refresh_devices
start_ui_updates
# Initialize transcription state
set transcribing false

# Start audio stream immediately for energy monitoring
start_audio_stream

if {$test_mode} {
    puts "TEST-MODE: Application initialized with instrumentation enabled"
    puts "Auto-starting transcription in test mode..."
    # Auto-start transcription in test mode
    after 1000 toggle_transcription
    puts "Background energy monitoring active"
}

puts "✓ Talkie Tcl Edition ready - Python-like interface"

# Force text view to be displayed at startup after all UI is initialized
after idle {
    set current_view ""
    show_text_view
}

# Handle window close
wm protocol . WM_DELETE_WINDOW quit_app
