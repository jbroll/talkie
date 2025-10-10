#!/usr/bin/env tclsh

package require Tk

# Create the main window
wm title . "Text Widget Retrieval Test"
wm geometry . "600x400"

# Create text widget
text .textwidget -wrap word -font {Courier 12} -width 60 -height 20
pack .textwidget -fill both -expand true -padx 10 -pady 10

# Test string
set test_string "Hello World! 123 @#$%"

proc test_text_retrieval {} {
    global test_string

    puts "=== Text Widget Retrieval Test ==="

    # Clear and insert test text
    .textwidget delete 1.0 end
    .textwidget insert end $test_string

    puts "Inserted: '$test_string'"
    puts "Length  : [string length $test_string]"

    # Try different methods to get text
    puts "\n--- Testing different retrieval methods ---"

    # Method 1: get 1.0 end
    set text1 [.textwidget get 1.0 end]
    puts "Method 1 (.textwidget get 1.0 end):"
    puts "  Result: '$text1'"
    puts "  Length: [string length $text1]"

    # Method 2: get 1.0 "end-1c"
    set text2 [.textwidget get 1.0 "end-1c"]
    puts "Method 2 (.textwidget get 1.0 \"end-1c\"):"
    puts "  Result: '$text2'"
    puts "  Length: [string length $text2]"

    # Method 3: get 1.0 "end linestart"
    set text3 [.textwidget get 1.0 "end linestart"]
    puts "Method 3 (.textwidget get 1.0 \"end linestart\"):"
    puts "  Result: '$text3'"
    puts "  Length: [string length $text3]"

    # Compare results
    puts "\n--- Comparison ---"
    if {$text2 eq $test_string} {
        puts "✓ Method 2 matches perfectly!"
    } else {
        puts "✗ Method 2 does not match"
        puts "Expected: '$test_string'"
        puts "Got     : '$text2'"
    }

    # Test inserting more text
    puts "\n--- Testing append ---"
    .textwidget insert end " APPENDED"
    set text_after_append [.textwidget get 1.0 "end-1c"]
    puts "After append: '$text_after_append'"

    # Auto-close
    after 5000 {destroy .}
}

# Instructions in text widget
.textwidget insert end "Text Widget Retrieval Test\n"
.textwidget insert end "=========================\n\n"
.textwidget insert end "This will test different methods to retrieve text from the widget.\n"
.textwidget insert end "Check console output for results.\n\n"
.textwidget insert end "Starting test in 2 seconds...\n"

# Start test
after 2000 test_text_retrieval

# Make window visible
wm deiconify .
tkwait window .