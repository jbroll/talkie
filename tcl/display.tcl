# display.tcl - Display management for Talkie

namespace eval ::display {
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
