#!/usr/bin/env tclsh
# Simple GUI test

package require Tk

# Test basic Tk functionality
wm title . "Test GUI"
wm geometry . 400x300

button .test -text "Hello Talkie!" -command {puts "Button clicked!"}
pack .test -pady 20

label .status -text "GUI test working"
pack .status

after 3000 {
    puts "GUI test completed"
    exit
}

puts "GUI created successfully"