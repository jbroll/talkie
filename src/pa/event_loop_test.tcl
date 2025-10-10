#!/usr/bin/env tclsh

# Test the Tcl event loop integration with PortAudio callbacks
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

package require pa
Pa_Init

puts "Testing Tcl event loop integration..."

set ::callback_received 0
set ::test_complete 0

# Callback that sets a flag
proc test_callback {stream timestamp data} {
    puts "*** CALLBACK RECEIVED: [string length $data] bytes at $timestamp ***"
    set ::callback_received 1
    # Don't stop immediately, let a few more callbacks through
}

# Create stream with callback
set stream [pa::open_stream -device default -rate 44100 -channels 1 -frames 256 -format float32 -callback test_callback]

puts "Created stream: [$stream info]"

# Start the stream
$stream start
puts "Stream started"

# Use vwait to properly enter the Tcl event loop
# This should allow the file handler to be processed
puts "Entering Tcl event loop (waiting for callbacks)..."

# Set up a timer to stop the test
after 3000 {
    puts "Timeout reached"
    set ::test_complete 1
}

# Also set up periodic status checks
proc check_status {} {
    global stream
    if {[catch {set stats [$stream stats]} err]} {
        puts "Error getting stats: $err"
        set ::test_complete 1
        return
    }

    puts "Stream stats: $stats - Callback received: $::callback_received"

    if {!$::test_complete} {
        after 500 check_status
    }
}

after 500 check_status

# Wait in the event loop
vwait ::test_complete

puts "Stopping stream..."
$stream stop
$stream close

if {$::callback_received} {
    puts "✓ SUCCESS: Audio callback was received!"
} else {
    puts "✗ FAILED: No audio callback received"
    puts "This indicates an issue with:"
    puts "  - Tcl file handler registration"
    puts "  - Audio thread to main thread communication"
    puts "  - Event loop processing"
}

puts "Test complete."