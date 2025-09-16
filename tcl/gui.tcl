# gui.tcl - GUI management for Talkie
package require Tk
package require Ttk

namespace eval ::gui {
    variable current_view "text"
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

        # View switching buttons (left-center)
        button .controls \
            -text "Controls" \
            -command ::gui::show_controls_view
        pack .controls -in $button_frame -side left -padx 5 -pady 0

        button .text \
            -text "Text" \
            -command ::gui::show_text_view \
            -relief sunken
        pack .text -in $button_frame -side left -pady 0

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

        # Quit button (flush right)
        button .quit \
            -text "Quit" \
            -command ::gui::quit_app
        pack .quit -in $button_frame -side right -pady 0

        frame .content
        pack .content -fill both -expand true -padx 10 -pady 5
    }

    proc setup_switchable_panes {} {
        # Controls pane with scrolling
        frame .controls_pane
        setup_controls_pane

        # Text pane
        frame .text_pane
        setup_text_pane

        # Note: Text view will be shown after all UI setup is complete
    }

    proc setup_controls_pane {} {
        # Create canvas and scrollbar for scrolling
        canvas .controls_canvas
        scrollbar .controls_scrollbar \
            -orient vertical -command ".controls_canvas yview"

        # Create scrollable frame inside canvas
        frame .controls_frame

        # Configure canvas
        .controls_canvas configure -yscrollcommand ".controls_scrollbar set"
        .controls_canvas create window 0 0 -window .controls_frame -anchor nw

        # Pack canvas and scrollbar in controls pane
        pack .controls_canvas -in .controls_pane -side left -fill both -expand true
        pack .controls_scrollbar -in .controls_pane -side right -fill y

        # Bind mousewheel and configure events
        bind .controls_frame <Configure> {
            .controls_canvas configure -scrollregion [.controls_canvas bbox all]
        }

        # Mouse wheel bindings
        bind .controls_canvas <MouseWheel> {
            .controls_canvas yview scroll [expr {-1 * (%D / 120)}] units
        }
        bind .controls_canvas <Button-4> {
            .controls_canvas yview scroll -1 units
        }
        bind .controls_canvas <Button-5> {
            .controls_canvas yview scroll 1 units
        }

        # Setup controls within scrollable frame
        setup_controls_content
    }

    proc setup_controls_content {} {
        set controls_container [frame .controls_frame.container]
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

    proc setup_text_pane {} {
        # Main text frame
        set text_frame [frame .text_pane.textframe]
        pack $text_frame -in .text_pane -pady 10 -fill both -expand true

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

    # View switching functions - matching Python exactly
    proc show_controls_view {} {
        variable current_view

        if {$current_view eq "controls"} return

        # Hide text pane, show controls pane
        if {[winfo exists .text_pane]} {
            pack forget .text_pane
        }
        pack .controls_pane -in .content -fill both -expand true

        # Update button states
        .controls config -relief sunken
        .text config -relief raised

        set current_view "controls"
    }

    proc show_text_view {} {
        variable current_view

        if {$current_view eq "text"} return

        # Hide controls pane, show text pane
        if {[winfo exists .controls_pane]} {
            pack forget .controls_pane
        }
        pack .text_pane -in .content -fill both -expand true

        # Update button states
        .text config -relief sunken
        .controls config -relief raised

        set current_view "text"
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

    proc initialize {} {
        setup_main_window
        setup_button_frame
        setup_switchable_panes

        # Set up window close handler
        wm protocol . WM_DELETE_WINDOW ::gui::quit_app

        # Add trace to update button when ::transcribing changes
        trace add variable ::transcribing write {::gui::update_transcription_button ;#}
    }

    proc show_default_view {} {
        variable current_view
        set current_view ""
        show_text_view
    }
}
