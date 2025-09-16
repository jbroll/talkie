# display.tcl - Display management for Talkie

namespace eval ::display {

    proc update_energy_display {} {
        set current_energy [::audio::get_energy]
        set current_confidence [::vosk::get_confidence]

        # Direct widget access

        # Update energy display
        .energy config -text [format "Audio: %.1f" $current_energy]

        # Color code energy level
        if {$current_energy > 50.0} {
            .energy config -bg "#4CAF50" -fg white
        } elseif {$current_energy > 20.0} {
            .energy config -bg "#FF9800" -fg white
        } elseif {$current_energy > 0.0} {
            .energy config -bg "#2196F3" -fg white
        } else {
            .energy config -bg "#f44336" -fg white
        }

        # Update confidence display
        .confidence config -text [format "Conf: %.0f" $current_confidence]

        # Color code confidence
        if {$current_confidence >= 320} {
            .confidence config -bg "#4CAF50" -fg white
        } elseif {$current_confidence >= 280} {
            .confidence config -bg "#FF9800" -fg white
        } else {
            .confidence config -bg "#f44336" -fg white
        }
    }

    proc start_ui_updates {} {
        update_energy_display
        after 100 ::display::start_ui_updates
    }

    proc display_final_text {text confidence} {

        set timestamp [clock format [clock seconds] -format "%H:%M:%S"]

        .final config -state normal

        # Check if we need to remove old lines (rolling buffer)
        if {$::gui::current_lines >= $::gui::max_lines} {
            # Remove the first line to make room
            .final delete 1.0 2.0
        } else {
            incr ::gui::current_lines
        }

        # Add new line at the end
        .final insert end "$timestamp " "timestamp"
        .final insert end "([format "%.0f" $confidence]): $text\n" "final"

        # Always keep the view at the bottom (most recent text)
        .final see end
        .final config -state disabled
    }

    proc update_partial_text {text} {
        .partial config -state normal
        .partial delete 1.0 end
        .partial insert end $text
        .partial config -state disabled
    }
}