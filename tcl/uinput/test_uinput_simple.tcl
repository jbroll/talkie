#!/usr/bin/env tclsh

package require Tk
package require uinput

# Create the main window
wm title . "Simple UInput Test"
wm geometry . "600x400"

# Create text widget
text .textwidget -wrap word -font {Courier 12} -width 60 -height 20
pack .textwidget -fill both -expand true -padx 10 -pady 10

# Status label
label .status -text "Ready to test..." -fg blue -font {Arial 12 bold}
pack .status -pady 5

# Simple test string
set test_string "Hello123"

proc run_simple_test {} {
    global test_string

    puts "=== Simple UInput Test ==="

    # Step 1: Test manual insertion
    .status configure -text "Step 1: Testing manual text insertion..." -fg blue
    update

    .textwidget delete 1.0 end
    .textwidget insert end $test_string

    set manual_result [.textwidget get 1.0 "end-1c"]
    puts "Manual insertion result: '$manual_result'"

    if {$manual_result eq $test_string} {
        puts "✓ Manual insertion working"
        .status configure -text "✓ Manual insertion working" -fg green
    } else {
        puts "✗ Manual insertion failed"
        .status configure -text "✗ Manual insertion failed" -fg red
        return
    }

    after 2000

    # Step 2: Test uinput initialization
    .status configure -text "Step 2: Testing uinput initialization..." -fg blue
    update

    if {[catch {uinput::init} result]} {
        puts "✗ UInput init failed: $result"
        .status configure -text "✗ UInput init failed" -fg red
        return
    }

    puts "✓ UInput initialized"
    .status configure -text "✓ UInput initialized" -fg green
    after 1000

    # Step 3: Clear widget and prepare for uinput test
    .status configure -text "Step 3: Clearing widget for uinput test..." -fg blue
    update

    .textwidget delete 1.0 end
    after 1000

    # Step 4: Test if we can see the current content
    set empty_content [.textwidget get 1.0 "end-1c"]
    puts "Widget content after clear: '$empty_content' (length: [string length $empty_content])"

    # Step 5: Try uinput typing
    .status configure -text "Step 4: Testing uinput typing..." -fg orange
    update

    # Give user time to ensure focus is on this window
    puts "About to type '$test_string' with uinput..."
    puts "Make sure this window has focus!"

    # Try to ensure window focus
    raise .
    focus -force .textwidget
    update
    after 1000

    # Type with uinput
    uinput::type $test_string

    # Wait for typing to complete
    after 5000 { set ::forme 1}
    vwait ::forme

    # Check result
    set uinput_result [.textwidget get 1.0 "end-1c"]
    puts "UInput result: '$uinput_result' (length: [string length $uinput_result])"

    if {$uinput_result eq $test_string} {
        puts "✓ SUCCESS: UInput typing worked!"
        .status configure -text "✓ SUCCESS: UInput typing worked!" -fg darkgreen
    } else {
        puts "✗ UInput typing failed or went elsewhere"
        puts "Expected: '$test_string'"
        puts "Got     : '$uinput_result'"
        .status configure -text "✗ UInput typing failed or went elsewhere" -fg red
    }

    # Cleanup
    uinput::cleanup

    # Auto-close
    after 5000 {destroy .}
}

# Instructions
.textwidget insert end "Simple UInput Test\n"
.textwidget insert end "==================\n\n"
.textwidget insert end "This test will:\n"
.textwidget insert end "1. Test manual text insertion\n"
.textwidget insert end "2. Initialize uinput\n"
.textwidget insert end "3. Clear this widget\n"
.textwidget insert end "4. Type '$test_string' using uinput\n"
.textwidget insert end "5. Check if the text appears here\n\n"
.textwidget insert end "Starting test in 3 seconds...\n"

# Start test
after 3000 run_simple_test

# Make window visible
wm deiconify .
tkwait window .
