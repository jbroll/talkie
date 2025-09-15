#!/usr/bin/env tclsh
# Test rolling buffer behavior

package require Tk

# Setup
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir vosk lib]
lappend auto_path [file join $script_dir audio lib]
set ::env(TCLLIBPATH) "$::env(HOME)/.local/lib"

# Load packages quietly
package require pa > /dev/null 2>&1
package require vosk > /dev/null 2>&1
package require audio > /dev/null 2>&1

# Create test window
wm title . "Rolling Buffer Test"
wm geometry . 600x400

# Create text widget without scrollbar
set ui(final_text) [text .text -wrap word -width 80 -height 12]
pack $ui(final_text) -fill both -expand true -padx 10 -pady 10

# Configure tags
$ui(final_text) tag configure "final" -foreground "black"
$ui(final_text) tag configure "timestamp" -foreground "gray" -font [list Arial 8]

# Initialize rolling buffer
set ui(max_lines) 15
set ui(current_lines) 0

# Test function - same as in main app
proc display_final_text {text confidence} {
    global ui

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

# Test with simulated transcriptions
proc test_rolling {} {
    set test_texts {
        "Hello world this is a test"
        "The quick brown fox jumps over the lazy dog"
        "Speech recognition is working well"
        "This line should appear at the bottom"
        "Old lines should disappear from the top"
        "We are testing the rolling buffer"
        "New text always goes to the bottom"
        "The oldest text gets removed automatically"
        "This keeps the display clean and current"
        "Line ten of our test sequence"
        "Line eleven should push out line one"
        "Line twelve continues the test"
        "Line thirteen keeps going"
        "Line fourteen is almost there"
        "Line fifteen fills the buffer"
        "Line sixteen should remove line one"
        "Line seventeen should remove line two"
        "Line eighteen should remove line three"
        "Final test line to verify rolling"
    }

    set i 0
    foreach text $test_texts {
        set confidence [expr {280 + rand() * 120}]
        display_final_text $text $confidence

        incr i
        puts "Added line $i: '$text'"

        after 1000
        update
    }
}

# Add control buttons
frame .controls
pack .controls -fill x -pady 5

button .controls.test -text "Test Rolling Buffer" -command test_rolling
pack .controls.test -side left -padx 5

button .controls.clear -text "Clear" -command {
    $ui(final_text) config -state normal
    $ui(final_text) delete 1.0 end
    $ui(final_text) config -state disabled
    set ui(current_lines) 0
}
pack .controls.clear -side left -padx 5

button .controls.quit -text "Quit" -command exit
pack .controls.quit -side right -padx 5

puts "Rolling Buffer Test Ready"
puts "Click 'Test Rolling Buffer' to see the effect"
puts "- New lines appear at bottom"
puts "- Old lines disappear from top after 15 lines"
puts "- No scrollbar needed"