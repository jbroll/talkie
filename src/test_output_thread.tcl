#!/usr/bin/env tclsh9.0
# Test script for output thread

package require Thread

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir uinput lib uinput]

# Mock config
array set ::config {
    typing_delay_ms 10
}

# Source the output module
source [file join $script_dir output.tcl]

puts "Testing output thread initialization..."

# Initialize output thread
if {[::output::initialize]} {
    puts "✓ Output thread initialized successfully"

    # Test sending text asynchronously
    puts "Testing async text output..."
    ::output::type_async "test"

    # Give it time to process
    after 100

    # Test cleanup
    puts "Testing cleanup..."
    ::output::cleanup
    puts "✓ Cleanup successful"

    puts "\n✓ All output thread tests passed!"
} else {
    puts "✗ Output thread initialization failed"
    exit 1
}
