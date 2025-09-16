# gui.tcl - GUI management for Talkie
package require Tk
package require Ttk

namespace eval ::gui {
    variable ui
    variable current_view "text"

    # UI variables
    array set ui {}

    proc setup_main_window {} {
        # Setup main window - matching Python exactly
        wm title . "Talkie"
        wm geometry . "800x500+[::config::get window_x]+[::config::get window_y]"
        wm minsize . 800 400
    }

    proc setup_button_frame {} {
        variable ui

        # Button row frame - EXACTLY matching Python layout
        set button_frame [frame .buttons]
        pack $button_frame -fill x -pady 10

        # Main transcription toggle button (flush left)
        set ui(toggle_btn) [button $button_frame.toggle \
            -text "Start Transcription" \
            -command ::gui::toggle_transcription \
            -activebackground "indianred"]
        pack $ui(toggle_btn) -side left -pady 0

        # View switching buttons (left-center)
        set ui(controls_btn) [button $button_frame.controls \
            -text "Controls" \
            -command ::gui::show_controls_view]
        pack $ui(controls_btn) -side left -padx 5 -pady 0

        set ui(text_btn) [button $button_frame.text \
            -text "Text" \
            -command ::gui::show_text_view \
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
            -command ::gui::quit_app]
        pack $ui(quit_btn) -side right -pady 0

        set ui(content_frame) [frame .content]
        pack $ui(content_frame) -fill both -expand true -padx 10 -pady 5
    }

    proc setup_switchable_panes {} {
        variable ui

        # Controls pane with scrolling
        set ui(controls_pane) [frame $ui(content_frame).controls]
        setup_controls_pane

        # Text pane
        set ui(text_pane) [frame $ui(content_frame).text]
        setup_text_pane

        # Note: Text view will be shown after all UI setup is complete
    }

    proc setup_controls_pane {} {
        variable ui

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
            $::gui::ui(controls_canvas) configure -scrollregion [$::gui::ui(controls_canvas) bbox all]
        }

        # Mouse wheel bindings
        bind $ui(controls_canvas) <MouseWheel> {
            $::gui::ui(controls_canvas) yview scroll [expr {-1 * (%D / 120)}] units
        }
        bind $ui(controls_canvas) <Button-4> {
            $::gui::ui(controls_canvas) yview scroll -1 units
        }
        bind $ui(controls_canvas) <Button-5> {
            $::gui::ui(controls_canvas) yview scroll 1 units
        }

        # Setup controls within scrollable frame
        setup_controls_content
    }

    proc setup_controls_content {} {
        variable ui

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
            -textvariable ::gui::ui(device_var) \
            -indicatoron 1 \
            -relief raised \
            -bd 2 \
            -highlightthickness 2 \
            -anchor w]
        pack $ui(device_menubutton) -side left -fill x -expand true

        set ui(device_menu) [menu $ui(device_menubutton).menu -tearoff 0]
        $ui(device_menubutton) config -menu $ui(device_menu)

        button $device_control_frame.refresh -text "Refresh" -command ::device::refresh_devices
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
            -from 0 -to 100 -resolution 5 -orient horizontal \
            -command ::gui::energy_changed]
        pack $ui(energy_scale) -fill x -expand true
        $ui(energy_scale) set [::config::get energy_threshold]

        # Silence trailing duration row
        set silence_frame [frame $controls_container.silence]
        pack $silence_frame -fill x -pady 2

        label $silence_frame.label -text "Silence Duration (s):" -width 20 -anchor w
        pack $silence_frame.label -side left

        set silence_control_frame [frame $silence_frame.control]
        pack $silence_control_frame -side right -fill x -expand true

        set ui(silence_scale) [scale $silence_control_frame.scale \
            -from 0.1 -to 2.0 -resolution 0.1 -orient horizontal \
            -command ::gui::silence_changed]
        pack $ui(silence_scale) -fill x -expand true
        $ui(silence_scale) set [::config::get silence_trailing_duration]

        # Confidence threshold row
        set confidence_frame [frame $controls_container.confidence]
        pack $confidence_frame -fill x -pady 2

        label $confidence_frame.label -text "Confidence Threshold:" -width 20 -anchor w
        pack $confidence_frame.label -side left

        set confidence_control_frame [frame $confidence_frame.control]
        pack $confidence_control_frame -side right -fill x -expand true

        set ui(confidence_scale) [scale $confidence_control_frame.scale \
            -from 0 -to 400 -resolution 10 -orient horizontal \
            -command ::gui::confidence_changed]
        pack $ui(confidence_scale) -fill x -expand true
        $ui(confidence_scale) set [::config::get confidence_threshold]

        # Vosk beam row
        set beam_frame [frame $controls_container.beam]
        pack $beam_frame -fill x -pady 2

        label $beam_frame.label -text "Vosk Beam:" -width 20 -anchor w
        pack $beam_frame.label -side left

        set beam_control_frame [frame $beam_frame.control]
        pack $beam_control_frame -side right -fill x -expand true

        set ui(beam_scale) [scale $beam_control_frame.scale \
            -from 5 -to 50 -resolution 1 -orient horizontal \
            -command ::gui::beam_changed]
        pack $ui(beam_scale) -fill x -expand true
        $ui(beam_scale) set [::config::get vosk_beam]

        # Vosk lattice beam row
        set lattice_frame [frame $controls_container.lattice]
        pack $lattice_frame -fill x -pady 2

        label $lattice_frame.label -text "Lattice Beam:" -width 20 -anchor w
        pack $lattice_frame.label -side left

        set lattice_control_frame [frame $lattice_frame.control]
        pack $lattice_control_frame -side right -fill x -expand true

        set ui(lattice_scale) [scale $lattice_control_frame.scale \
            -from 1 -to 20 -resolution 1 -orient horizontal \
            -command ::gui::lattice_changed]
        pack $ui(lattice_scale) -fill x -expand true
        $ui(lattice_scale) set [::config::get vosk_lattice_beam]

        # Vosk alternatives row
        set alternatives_frame [frame $controls_container.alternatives]
        pack $alternatives_frame -fill x -pady 2

        label $alternatives_frame.label -text "Max Alternatives:" -width 20 -anchor w
        pack $alternatives_frame.label -side left

        set alternatives_control_frame [frame $alternatives_frame.control]
        pack $alternatives_control_frame -side right -fill x -expand true

        set ui(alternatives_scale) [scale $alternatives_control_frame.scale \
            -from 0 -to 5 -resolution 1 -orient horizontal \
            -command ::gui::alternatives_changed]
        pack $ui(alternatives_scale) -fill x -expand true
        $ui(alternatives_scale) set [::config::get vosk_max_alternatives]

        # Lookback duration row
        set lookback_frame [frame $controls_container.lookback]
        pack $lookback_frame -fill x -pady 2

        label $lookback_frame.label -text "Lookback Duration (s):" -width 20 -anchor w
        pack $lookback_frame.label -side left

        set lookback_control_frame [frame $lookback_frame.control]
        pack $lookback_control_frame -side right -fill x -expand true

        set ui(lookback_scale) [scale $lookback_control_frame.scale \
            -from 0.1 -to 3.0 -resolution 0.1 -orient horizontal \
            -command ::gui::lookback_changed]
        pack $ui(lookback_scale) -fill x -expand true
        $ui(lookback_scale) set [::config::get lookback_duration]
    }

    proc setup_text_pane {} {
        variable ui

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
        variable ui
        variable current_view

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
        variable ui
        variable current_view

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
        variable ui

        set transcribing [::audio::toggle_transcription]

        if {$transcribing} {
            $ui(toggle_btn) config -text "Stop Transcription" -bg "#f44336" -fg white
        } else {
            $ui(toggle_btn) config -text "Start Transcription" -bg "#4CAF50" -fg white
        }
    }

    # Control change handlers
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
        update_config_param lookback_duration $value
        # Convert seconds to frames: each buffer is ~0.1 seconds (4410 frames at 44100 Hz)
        # So frames = duration * 10, rounded to nearest integer
        set frames [expr {int($value * 10 + 0.5)}]
        ::config::set_value lookback_frames $frames
        update_config_param lookback_frames $frames
    }

    proc quit_app {} {
        ::audio::stop_transcription

        if {[catch {pa::terminate}]} {
            # Ignore cleanup errors
        }

        exit
    }

    # Provide access to UI elements for other modules
    proc get_ui_element {name} {
        variable ui
        return $ui($name)
    }

    proc set_ui_var {name value} {
        variable ui
        set ui($name) $value
    }

    proc initialize {} {
        setup_main_window
        setup_button_frame
        setup_switchable_panes

        # Set up window close handler
        wm protocol . WM_DELETE_WINDOW ::gui::quit_app
    }

    proc show_default_view {} {
        variable current_view
        set current_view ""
        show_text_view
    }
}
