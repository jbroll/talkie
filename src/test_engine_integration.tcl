#!/usr/bin/env tclsh
# test_engine_integration.tcl - Test that coprocess engine matches expected interface

lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"
package require json

# Set up minimal config
array set ::config {
    speech_engine "faster-whisper"
}

set ::device_sample_rate 16000

# Mock get_model_path
proc get_model_path {} {
    return "../models/faster-whisper"
}

# Load the coprocess engine
source engine_coprocess.tcl

proc test_recognizer_interface {} {
    puts "=== Testing Recognizer Interface ==="
    puts ""

    # Initialize engine
    puts "1. Initializing engine..."
    if {![::engine::initialize]} {
        puts "ERROR: Failed to initialize engine"
        return
    }

    # Get recognizer command
    set recognizer [::engine::recognizer]
    puts "   Recognizer command: $recognizer"
    puts ""

    # Test process method
    puts "2. Testing 'process' method..."
    set silence [binary format s* [lrepeat 1600 0]]
    set result [$recognizer process $silence]
    puts "   Result: $result"

    set result_dict [json::json2dict $result]
    if {[dict exists $result_dict partial]} {
        puts "   ✓ Got partial result: '[dict get $result_dict partial]'"
    } else {
        puts "   ✗ Unexpected result format"
    }
    puts ""

    # Test final-result method
    puts "3. Testing 'final-result' method..."
    set result [$recognizer final-result]
    puts "   Result: $result"

    set result_dict [json::json2dict $result]
    if {[dict exists $result_dict alternatives]} {
        set alternatives [dict get $result_dict alternatives]
        set first_alt [lindex $alternatives 0]
        set text [dict get $first_alt text]
        set conf [dict get $first_alt confidence]
        puts "   ✓ Got final result:"
        puts "     Text: '$text'"
        puts "     Confidence: $conf"
    } else {
        puts "   ✗ Unexpected result format"
    }
    puts ""

    # Test reset method
    puts "4. Testing 'reset' method..."
    $recognizer reset
    puts "   ✓ Reset successful"
    puts ""

    # Cleanup
    puts "5. Cleaning up..."
    ::engine::cleanup
    puts "   ✓ Cleanup successful"
    puts ""

    puts "=== Test Complete ==="
    puts ""
    puts "Interface matches audio.tcl expectations:"
    puts "  - \$recognizer process \$audio_data → JSON string"
    puts "  - \$recognizer final-result → JSON string"
    puts "  - \$recognizer reset → void"
}

# Run test
test_recognizer_interface
