# display.tcl - Display management for Talkie

namespace eval ::display {

    proc update_energy_display {} {
        set current_energy [::audio::get_energy]
        set current_confidence [::vosk::get_confidence]

        # Get UI elements
        set energy_label [::gui::get_ui_element energy_label]
        set confidence_label [::gui::get_ui_element confidence_label]

        # Update energy display
        $energy_label config -text [format "Audio: %.1f" $current_energy]

        # Color code energy level
        if {$current_energy > 50.0} {
            $energy_label config -bg "#4CAF50" -fg white
        } elseif {$current_energy > 20.0} {
            $energy_label config -bg "#FF9800" -fg white
        } elseif {$current_energy > 0.0} {
            $energy_label config -bg "#2196F3" -fg white
        } else {
            $energy_label config -bg "#f44336" -fg white
        }

        # Update confidence display
        $confidence_label config -text [format "Conf: %.0f" $current_confidence]

        # Color code confidence
        if {$current_confidence >= 320} {
            $confidence_label config -bg "#4CAF50" -fg white
        } elseif {$current_confidence >= 280} {
            $confidence_label config -bg "#FF9800" -fg white
        } else {
            $confidence_label config -bg "#f44336" -fg white
        }
    }

    proc start_ui_updates {} {
        update_energy_display
        after 100 ::display::start_ui_updates
    }

    proc display_final_text {text confidence} {
        set final_text [::gui::get_ui_element final_text]

        set timestamp [clock format [clock seconds] -format "%H:%M:%S"]

        $final_text config -state normal

        # Check if we need to remove old lines (rolling buffer)
        set max_lines [::gui::get_ui_element max_lines]
        set current_lines [::gui::get_ui_element current_lines]

        if {$current_lines >= $max_lines} {
            # Remove the first line to make room
            $final_text delete 1.0 2.0
        } else {
            ::gui::set_ui_var current_lines [expr {$current_lines + 1}]
        }

        # Add new line at the end
        $final_text insert end "$timestamp " "timestamp"
        $final_text insert end "([format "%.0f" $confidence]): $text\n" "final"

        # Always keep the view at the bottom (most recent text)
        $final_text see end
        $final_text config -state disabled
    }

    proc update_partial_text {text} {
        set partial_text [::gui::get_ui_element partial_text]

        $partial_text config -state normal
        $partial_text delete 1.0 end
        $partial_text insert end $text
        $partial_text config -state disabled
    }
}