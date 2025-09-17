# gui.tcl - GUI management for Talkie
package require Tk
package require Ttk

namespace eval ::gui {
    variable max_lines 15
    variable current_lines 0

    proc setup_main_window {} {
        # Setup main window - matching Python exactly
        wm title . "Talkie"
        wm geometry . "800x500+$::config::config(window_x)+$::config::config(window_y)"
        wm minsize . 800 400
    }

    proc setup_button_frame {} {
        variable ui

        # Button row frame - EXACTLY matching Python layout
        set button_frame [frame .buttons]
        pack $button_frame -fill x -pady 10

        # Main transcription toggle button (flush left)
        button .toggle \
            -text "Start Transcription" \
            -command ::gui::toggle_transcription \
            -activebackground "indianred"
        pack .toggle -in $button_frame -side left -pady 0


        # Audio energy display (center-left) - styled like Python
        label .energy \
            -text "Audio: 0" \
            -relief raised -bd 2 \
            -padx 10 -pady 5 \
            -font [list Arial 10]
        pack .energy -in $button_frame -side left -expand true -padx {10 5} -pady 0

        # Confidence display (center-right) - styled like Python
        label .confidence \
            -text "Conf: --" \
            -relief raised -bd 2 \
            -padx 10 -pady 5 \
            -font [list Arial 10]
        pack .confidence -in $button_frame -side left -expand true -padx {5 10} -pady 0

        # Config and Quit buttons (flush right)
        button .quit \
            -text "Quit" \
            -command ::gui::quit_app
        pack .quit -in $button_frame -side right -pady 0

        button .config \
            -text "Config" \
            -command ::gui::show_config_dialog
        pack .config -in $button_frame -side right -padx {0 5} -pady 0

        frame .content
        pack .content -fill both -expand true -padx 10 -pady 5
    }

    proc setup_text_pane {} {
        # Main text frame directly in .content
        set text_frame [frame .content.textframe]
        pack $text_frame -pady 10 -fill both -expand true

        # Final results history (top, large) - rolling buffer without scrollbar
        text .final -wrap word -width 80 -height 12
        pack .final -in $text_frame -fill both -expand true -pady {0 5}

        # Configure tags for final results
        .final tag configure "final" -foreground "black"
        .final tag configure "timestamp" -foreground "gray" -font [list Arial 8]

        # Current partial text (bottom, smaller) - matching Python
        set partial_frame [frame $text_frame.partial_frame]
        pack $partial_frame -fill x -pady {5 0}

        text .partial -wrap word -width 80 -height 3
        pack .partial -in $partial_frame -fill both -expand true

        # Configure tags for partial results
        .partial tag configure "sent" -foreground "gray"
    }

    proc show_config_dialog {} {
        # Create modal dialog
        if {[winfo exists .config_dialog]} {
            destroy .config_dialog
        }

        toplevel .config_dialog
        wm title .config_dialog "Configuration"
        wm geometry .config_dialog "500x600"
        wm transient .config_dialog .
        grab .config_dialog

        # Center the dialog
        wm withdraw .config_dialog
        update idletasks
        set x [expr {[winfo rootx .] + [winfo width .]/2 - 250}]
        set y [expr {[winfo rooty .] + [winfo height .]/2 - 300}]
        wm geometry .config_dialog +$x+$y
        wm deiconify .config_dialog

        # Create scrollable content
        canvas .config_dialog.canvas
        scrollbar .config_dialog.scrollbar \
            -orient vertical -command ".config_dialog.canvas yview"
        frame .config_dialog.content

        .config_dialog.canvas configure -yscrollcommand ".config_dialog.scrollbar set"
        .config_dialog.canvas create window 0 0 -window .config_dialog.content -anchor nw

        pack .config_dialog.canvas -side left -fill both -expand true
        pack .config_dialog.scrollbar -side right -fill y

        # Setup controls content
        setup_modal_controls_content .config_dialog.content

        # Configure scrolling
        bind .config_dialog.content <Configure> {
            .config_dialog.canvas configure -scrollregion [.config_dialog.canvas bbox all]
        }

        # Mouse wheel bindings
        bind .config_dialog.canvas <MouseWheel> {
            .config_dialog.canvas yview scroll [expr {-1 * (%D / 120)}] units
        }

        # Close button
        frame .config_dialog.buttons
        pack .config_dialog.buttons -side bottom -fill x -pady 10

        button .config_dialog.buttons.close \
            -text "Close" \
            -command "grab release .config_dialog; destroy .config_dialog"
        pack .config_dialog.buttons.close -pady 5

        # Focus and key bindings
        focus .config_dialog
        bind .config_dialog <Escape> "grab release .config_dialog; destroy .config_dialog"
    }

    proc setup_modal_controls_content {parent} {
        set controls_container [frame $parent.container]
        pack $controls_container -pady 10 -padx 20 -fill x

        # Device selection row - matching Python exactly
        set device_frame [frame $controls_container.device]
        pack $device_frame -fill x -pady 2

        label $device_frame.label -text "Audio Device:" -width 20 -anchor w
        pack $device_frame.label -side left

        set device_control_frame [frame $device_frame.control]
        pack $device_control_frame -side right -fill x -expand true

        # Create a proper dropdown using menubutton
        menubutton $device_control_frame.mb \
            -textvariable ::config::config(device) \
            -indicatoron 1 \
            -relief raised \
            -bd 2 \
            -highlightthickness 2 \
            -anchor w
        pack $device_control_frame.mb -side left -fill x -expand true

        menu $device_control_frame.mb.menu -tearoff 0
        $device_control_frame.mb config -menu $device_control_frame.mb.menu

        button $device_control_frame.refresh -text "Refresh" -command ::device::refresh_devices
        pack $device_control_frame.mb -side left -fill x -expand true -padx {0 5}
        pack $device_control_frame.refresh -side right

        # Energy threshold row
        set energy_frame [frame $controls_container.energy]
        pack $energy_frame -fill x -pady 2

        label $energy_frame.label -text "Energy Threshold:" -width 20 -anchor w
        pack $energy_frame.label -side left

        set energy_control_frame [frame $energy_frame.control]
        pack $energy_control_frame -side right -fill x -expand true

        scale $energy_control_frame.scale \
            -from 0 -to 100 -resolution 5 -orient horizontal \
            -variable ::config::config(energy_threshold)
        pack $energy_control_frame.scale -fill x -expand true

        # Silence trailing duration row
        set silence_frame [frame $controls_container.silence]
        pack $silence_frame -fill x -pady 2

        label $silence_frame.label -text "Silence Duration (s):" -width 20 -anchor w
        pack $silence_frame.label -side left

        set silence_control_frame [frame $silence_frame.control]
        pack $silence_control_frame -side right -fill x -expand true

        scale $silence_control_frame.scale \
            -from 0.1 -to 2.0 -resolution 0.1 -orient horizontal \
            -variable ::config::config(silence_trailing_duration)
        pack $silence_control_frame.scale -fill x -expand true

        # Confidence threshold row
        set confidence_frame [frame $controls_container.confidence]
        pack $confidence_frame -fill x -pady 2

        label $confidence_frame.label -text "Confidence Threshold:" -width 20 -anchor w
        pack $confidence_frame.label -side left

        set confidence_control_frame [frame $confidence_frame.control]
        pack $confidence_control_frame -side right -fill x -expand true

        scale $confidence_control_frame.scale \
            -from 0 -to 400 -resolution 10 -orient horizontal \
            -variable ::config::config(confidence_threshold)
        pack $confidence_control_frame.scale -fill x -expand true

        # Vosk beam row
        set beam_frame [frame $controls_container.beam]
        pack $beam_frame -fill x -pady 2

        label $beam_frame.label -text "Vosk Beam:" -width 20 -anchor w
        pack $beam_frame.label -side left

        set beam_control_frame [frame $beam_frame.control]
        pack $beam_control_frame -side right -fill x -expand true

        scale $beam_control_frame.scale \
            -from 5 -to 50 -resolution 1 -orient horizontal \
            -variable ::config::config(vosk_beam)
        pack $beam_control_frame.scale -fill x -expand true

        # Vosk lattice beam row
        set lattice_frame [frame $controls_container.lattice]
        pack $lattice_frame -fill x -pady 2

        label $lattice_frame.label -text "Lattice Beam:" -width 20 -anchor w
        pack $lattice_frame.label -side left

        set lattice_control_frame [frame $lattice_frame.control]
        pack $lattice_control_frame -side right -fill x -expand true

        scale $lattice_control_frame.scale \
            -from 1 -to 20 -resolution 1 -orient horizontal \
            -variable ::config::config(vosk_lattice_beam)
        pack $lattice_control_frame.scale -fill x -expand true

        # Vosk alternatives row
        set alternatives_frame [frame $controls_container.alternatives]
        pack $alternatives_frame -fill x -pady 2

        label $alternatives_frame.label -text "Max Alternatives:" -width 20 -anchor w
        pack $alternatives_frame.label -side left

        set alternatives_control_frame [frame $alternatives_frame.control]
        pack $alternatives_control_frame -side right -fill x -expand true

        scale $alternatives_control_frame.scale \
            -from 0 -to 5 -resolution 1 -orient horizontal \
            -variable ::config::config(vosk_max_alternatives)
        pack $alternatives_control_frame.scale -fill x -expand true

        # Lookback seconds row
        set lookback_frame [frame $controls_container.lookback]
        pack $lookback_frame -fill x -pady 2

        label $lookback_frame.label -text "Lookback Seconds:" -width 20 -anchor w
        pack $lookback_frame.label -side left

        set lookback_control_frame [frame $lookback_frame.control]
        pack $lookback_control_frame -side right -fill x -expand true

        scale $lookback_control_frame.scale \
            -from 0.1 -to 3.0 -resolution 0.1 -orient horizontal \
            -variable ::config::config(lookback_seconds)
        pack $lookback_control_frame.scale -fill x -expand true
    }



    # Event handlers
    proc toggle_transcription {} {
        ::audio::toggle_transcription
    }


    proc quit_app {} {
        ::audio::stop_transcription

        if {[catch {pa::terminate}]} {
            # Ignore cleanup errors
        }

        exit
    }


    proc update_transcription_button {} {
        if {$::transcribing} {
            .toggle config -text "Stop Transcription" -bg "#4CAF50" -fg white
        } else {
            .toggle config -text "Start Transcription" -bg "#f44336" -fg white
        }
    }

    proc update_window_position {} {
        # Get current window position
        set geom [wm geometry .]
        if {[regexp {^\d+x\d+\+(-?\d+)\+(-?\d+)$} $geom -> x y]} {
            set ::config::config(window_x) $x
            set ::config::config(window_y) $y
        }
    }

    proc initialize {} {
        setup_main_window
        setup_button_frame
        setup_text_pane

        # Set up window close handler
        wm protocol . WM_DELETE_WINDOW ::gui::quit_app

        # Track window position changes
        bind . <Configure> {
            if {"%W" eq "."} {
                ::gui::update_window_position
            }
        }

        # Add trace to update button when ::transcribing changes
        trace add variable ::transcribing write {::gui::update_transcription_button ;#}
    }
}
