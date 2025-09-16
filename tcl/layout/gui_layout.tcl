# gui_layout.tcl - Layout-based GUI for Talkie


namespace eval ::gui {
    # UI state array - should be a subset of config!
    variable ui

    proc init_ui_array {} {
        variable ui

        # Start with config values
        array set ui [::config::get_all]

        # Add UI-specific state (not in config)
        array set ui {
            current_view "text"
            energy_display "Audio: 0"
            confidence_display "Conf: --"
            transcribe_button_text "Start Transcription"
            max_lines 15
            current_lines 0
            device_list {}

            toggle_btn ""
            energy_label ""
            confidence_label ""
            content_frame ""
            final_text ""
            partial_text ""
        }
    }

    proc initialize {} {
        # Initialize UI array properly from config
        init_ui_array

        create_main_window
        ::device::refresh_devices
        show_text_view
    }

    proc create_main_window {} {
        variable ui

        wm title . "Talkie (Layout)"
        wm geometry . "800x600+[::config::get window_x]+[::config::get window_y]"
        wm minsize . 800 500

        # Create the main layout - using direct text for now, will add binding later
        layout -in . {
            # Global options
            -sticky ew
            -padx 5
            -pady 2
            -label.relief raised
            -label.bd 2

            # Main button row
            ! "Start Transcription" -command ::gui::toggle_transcription -width 15
            ! "Controls" -command ::gui::show_controls_view -width 10
            ! "Text" -command ::gui::show_text_view -width 10
            @ "Audio: 0" -width 12
            @ "Conf: --" -width 12
            ! "Quit" -command ::gui::quit_app -width 8

            # Content area (will be populated by view functions)
            & frame -background lightgray -height 400 - - - - -
        }

        # Store widget references for manual updates
        set ui(toggle_btn) .w4
        set ui(energy_label) .w7
        set ui(confidence_label) .w8
        set ui(content_frame) .w9

        # Configure window close
        wm protocol . WM_DELETE_WINDOW ::gui::quit_app
    }

    proc show_controls_view {args} {
        variable ui

        if {$ui(current_view) eq "controls"} return
        set ui(current_view) "controls"

        # Clear and repopulate content area
        if {[winfo exists $ui(content_frame)]} {
            foreach child [winfo children $ui(content_frame)] {
                destroy $child
            }
        }

        layout -in $ui(content_frame) {
            -sticky ew
            -padx 10
            -pady 5
            -colweight 1 1
            -label.width 20
            -label.anchor w

            @ "Audio Device:" optmenu -textvariable ::gui::device_name ! "Refresh" -command ::device::refresh_devices

            & @ "Energy Threshold:" scale -from 0 -to 100 -resolution 5 -orient horizontal -variable ::gui::energy_threshold -command ::gui::energy_changed
            & @ "Silence Duration (s):" scale -from 0.1 -to 2.0 -resolution 0.1 -orient horizontal -variable ::gui::silence_duration -command ::gui::silence_changed
            & @ "Confidence Threshold:" scale -from 0 -to 400 -resolution 10 -orient horizontal -variable ::gui::confidence_threshold -command ::gui::confidence_changed
            & @ "Vosk Beam:" scale -from 5 -to 50 -resolution 1 -orient horizontal -variable ::gui::vosk_beam -command ::gui::beam_changed
            & @ "Lattice Beam:" scale -from 1 -to 20 -resolution 1 -orient horizontal -variable ::gui::vosk_lattice_beam -command ::gui::lattice_changed
            & @ "Max Alternatives:" scale -from 0 -to 5 -resolution 1 -orient horizontal -variable ::gui::vosk_max_alternatives -command ::gui::alternatives_changed
            & @ "Lookback Duration (s):" scale -from 0.1 -to 3.0 -resolution 0.1 -orient horizontal -variable ::gui::lookback_duration -command ::gui::lookback_changed
        }
    }

    proc show_text_view {args} {
        variable ui

        if {$ui(current_view) eq "text"} return
        set ui(current_view) "text"

        # Clear and repopulate content area
        if {[winfo exists $ui(content_frame)]} {
            foreach child [winfo children $ui(content_frame)] {
                destroy $child
            }
        }

        layout -in $ui(content_frame) {
            -sticky news
            -padx 10
            -pady 5
            -colweight 0 1
            -rowweight 0 1
            -rowweight 1 0

            # Final text area (main, expandable)
            text -wrap word -width 80 -height 15 -state disabled

            # Partial text area (smaller, fixed)
            & text -wrap word -width 80 -height 3 -state disabled -background "#f0f0f0"
        }

        # Store widget references and configure tags
        set widgets [winfo children $ui(content_frame)]
        if {[llength $widgets] >= 2} {
            set ui(final_text) [lindex $widgets 0]
            set ui(partial_text) [lindex $widgets 1]

            $ui(final_text) tag configure "final" -foreground "black"
            $ui(final_text) tag configure "timestamp" -foreground "gray" -font [list Arial 8]
            $ui(partial_text) tag configure "partial" -foreground "blue"
        }
    }

    proc toggle_transcription {args} {
        variable ui

        set transcribing [::audio::toggle_transcription]

        if {$transcribing} {
            set ui(transcribe_button_text) "Stop Transcription"
            $ui(toggle_btn) config -text "Stop Transcription"
        } else {
            set ui(transcribe_button_text) "Start Transcription"
            $ui(toggle_btn) config -text "Start Transcription"
        }
    }

    # Configuration change handlers - now using proper config names!
    proc energy_changed {args} {
        variable ui
        ::config::update_param energy_threshold $ui(energy_threshold)
    }

    proc silence_changed {args} {
        variable ui
        ::config::update_param silence_trailing_duration $ui(silence_trailing_duration)
    }

    proc confidence_changed {args} {
        variable ui
        ::config::update_param confidence_threshold $ui(confidence_threshold)
    }

    proc beam_changed {args} {
        variable ui
        ::config::update_param vosk_beam $ui(vosk_beam)
    }

    proc lattice_changed {args} {
        variable ui
        ::config::update_param vosk_lattice_beam $ui(vosk_lattice_beam)
    }

    proc alternatives_changed {args} {
        variable ui
        ::config::update_param vosk_max_alternatives $ui(vosk_max_alternatives)
    }

    proc lookback_changed {args} {
        variable ui
        ::config::update_param lookback_duration $ui(lookback_duration)
        # Update frames calculation
        set frames [expr {int($ui(lookback_duration) * 10 + 0.5)}]
        ::config::set_value lookback_frames $frames
        ::config::update_param lookback_frames $frames
    }

    proc device_changed {args} {
        variable ui
        ::config::update_param device $ui(device)
    }

    proc update_device_list {devices} {
        variable ui
        set ui(device_list) $devices
    }

    # Accessor functions for ui array elements
    proc get_ui_element {name} {
        variable ui
        return $ui($name)
    }

    proc set_ui_element {name value} {
        variable ui
        set ui($name) $value
    }

    proc update_energy_display {energy} {
        variable ui
        set ui(energy_display) [format "Audio: %.1f" $energy]
        if {$ui(energy_label) ne ""} {
            $ui(energy_label) config -text $ui(energy_display)
        }
    }

    proc update_confidence_display {confidence} {
        variable ui
        set ui(confidence_display) [format "Conf: %.0f" $confidence]
        if {$ui(confidence_label) ne ""} {
            $ui(confidence_label) config -text $ui(confidence_display)
        }
    }

    proc quit_app {args} {
        ::audio::stop_transcription
        if {[catch {pa::terminate}]} {
            # Ignore cleanup errors
        }
        exit
    }

    # Direct text update functions for display module
    proc update_final_text {text confidence} {
        variable ui

        if {$ui(final_text) eq "" || ![winfo exists $ui(final_text)]} return

        set timestamp [clock format [clock seconds] -format "%H:%M:%S"]
        set widget $ui(final_text)

        $widget config -state normal
        $widget insert end "$timestamp " "timestamp"
        $widget insert end "([format "%.0f" $confidence]): $text\n" "final"

        # Keep only last max_lines (simple rolling buffer)
        set lines [split [$widget get 1.0 end] \n]
        if {[llength $lines] > [expr {$ui(max_lines) + 1}]} {
            $widget delete 1.0 2.0
        } else {
            incr ui(current_lines)
        }

        $widget see end
        $widget config -state disabled
    }

    proc update_partial_text {text} {
        variable ui

        if {$ui(partial_text) eq "" || ![winfo exists $ui(partial_text)]} return

        set widget $ui(partial_text)
        $widget config -state normal
        $widget delete 1.0 end
        $widget insert end $text "partial"
        $widget config -state disabled
    }
}
