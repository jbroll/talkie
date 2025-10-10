#!/usr/bin/env tclsh

package require Tk

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir lib uinput]
package require uinput

# Create the main window
wm title . "UInput Verification Test"
wm geometry . "800x600"

# Create text widget for receiving input
text .textwidget -wrap word -font {Courier 12} -width 80 -height 30
pack .textwidget -fill both -expand true -padx 10 -pady 10

# Status label
label .status -text "Starting automated test..." -fg blue -font {Arial 12 bold}
pack .status -pady 5

# Define the complete test string with all supported characters
set test_string "hello world HELLO WORLD 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ !@#\$%^&*()_+-=\{\}[]|\\:;\"'<>?/~`,./ space test"

proc run_test {} {
    global test_string

    puts "=== UInput Verification Test Starting ==="

    # Clear text widget
    .textwidget delete 1.0 end

    .status configure -text "Initializing uinput..." -fg orange
    update

    # Initialize uinput
    if {[catch {uinput::init} result]} {
        .status configure -text "FAILED: uinput init error: $result" -fg red
        puts "FAIL: uinput initialization failed: $result"
        return
    }

    .status configure -text "UInput initialized. Focusing text widget..." -fg blue
    update

    # Focus the text widget aggressively
    raise .
    focus -force .textwidget
    grab set .textwidget
    update idletasks

    # Verify focus was taken
    set focused_widget [focus]
    puts "Focus is on: $focused_widget"
    if {$focused_widget ne ".textwidget"} {
        puts "WARNING: Focus not on text widget!"
    }

    after 2000

    .status configure -text "Typing test string via uinput..." -fg green
    update

    puts "Expected: $test_string"
    puts "Typing via uinput..."

    # Type the test string
    uinput::type $test_string

    # Wait for typing to complete - use vwait to enter event loop
    after 5000 { set ::typing_done 1}
    vwait ::typing_done

    .status configure -text "Retrieving text from widget..." -fg blue
    update

    # Get the actual text from the widget
    set actual_text [.textwidget get 1.0 "end-1c"]

    puts "Actual  : $actual_text"

    # Compare expected vs actual
    if {$actual_text eq $test_string} {
        .status configure -text "✓ PASS: Text matches perfectly!" -fg darkgreen
        puts "RESULT: PASS - UInput wrapper working correctly!"
    } else {
        .status configure -text "✗ FAIL: Text does not match" -fg red
        puts "RESULT: FAIL - UInput wrapper has issues"
        puts "Expected length: [string length $test_string]"
        puts "Actual length  : [string length $actual_text]"

        # Show character-by-character differences
        set max_len [expr {max([string length $test_string], [string length $actual_text])}]
        puts "\nCharacter-by-character comparison:"
        for {set i 0} {$i < $max_len} {incr i} {
            set exp_char [string index $test_string $i]
            set act_char [string index $actual_text $i]
            if {$exp_char ne $act_char} {
                puts "Position $i: expected '$exp_char' ([scan $exp_char %c]) got '$act_char' ([scan $act_char %c])"
            }
        }
    }

    # Cleanup
    grab release .textwidget
    uinput::cleanup
    puts "=== Test Complete ==="

    # Auto-close after showing results
    after 5000 {destroy .}
}

# Instructions in the text widget initially
.textwidget insert end "UInput Automatic Verification Test\n"
.textwidget insert end "===================================\n\n"
.textwidget insert end "This test will:\n"
.textwidget insert end "1. Clear this text\n"
.textwidget insert end "2. Focus this widget\n"
.textwidget insert end "3. Use uinput to type a comprehensive test string\n"
.textwidget insert end "4. Compare expected vs actual text\n"
.textwidget insert end "5. Report PASS/FAIL to console\n\n"
.textwidget insert end "Test string includes:\n"
.textwidget insert end "- All lowercase letters\n"
.textwidget insert end "- All uppercase letters\n"
.textwidget insert end "- All digits 0-9\n"
.textwidget insert end "- All special characters: !@#\$%^&*()_+-={}[]|\\:;\"'<>?/~`,./\n\n"
.textwidget insert end "Starting test in 3 seconds...\n"

# Start the test after a short delay
after 3000 run_test

# Make sure window is visible
wm deiconify .
tkwait window .
