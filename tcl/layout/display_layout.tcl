# display_layout.tcl - Display management for Layout-based Talkie

namespace eval ::display {

    proc update_energy_display {} {
        set current_energy [::audio::get_energy]
        set current_confidence [::vosk::get_confidence]

        # Update GUI through the ui array using accessor functions
        ::gui::update_energy_display $current_energy
        ::gui::update_confidence_display $current_confidence

        # Color coding for energy levels
        set energy_label [::gui::get_ui_element energy_label]
        if {$energy_label ne ""} {
            if {$current_energy > 50.0} {
                $energy_label config -bg "#4CAF50" -fg white
            } elseif {$current_energy > 20.0} {
                $energy_label config -bg "#FF9800" -fg white
            } elseif {$current_energy > 0.0} {
                $energy_label config -bg "#2196F3" -fg white
            } else {
                $energy_label config -bg "#f44336" -fg white
            }
        }

        # Color coding for confidence levels
        set confidence_label [::gui::get_ui_element confidence_label]
        if {$confidence_label ne ""} {
            if {$current_confidence >= 320} {
                $confidence_label config -bg "#4CAF50" -fg white
            } elseif {$current_confidence >= 280} {
                $confidence_label config -bg "#FF9800" -fg white
            } else {
                $confidence_label config -bg "#f44336" -fg white
            }
        }
    }

    proc start_ui_updates {} {
        update_energy_display
        after 100 ::display::start_ui_updates
    }

    proc display_final_text {text confidence} {
        # Use the GUI module's direct text update function
        ::gui::update_final_text $text $confidence
    }

    proc update_partial_text {text} {
        # Use the GUI module's direct text update function
        ::gui::update_partial_text $text
    }
}