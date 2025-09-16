#!/usr/bin/env tclsh

package require Tk
source /home/john/src/jbr.tcl/layout/layout.tcl

set layout.debug 1

# Simple test of layout system
wm title . "Layout Test"

set button_text "Click Me"
set status_text "Ready"

layout -in . {
    -sticky ew
    -padx 5
    -pady 5

    ! "Simple Button" -command { puts "clicked" }
    @ ::status_text "Status Text"
    ! "Quit" -command exit
}

puts "Simple layout test running..."