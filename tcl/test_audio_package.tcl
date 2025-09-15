#!/usr/bin/env tclsh
# Test the new audio package

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir audio lib]

puts "Testing audio package..."

if {[catch {
    package require audio
    puts "✓ Audio package loaded: [package present audio]"

    # Test with sample 16-bit data (5 samples: 1000, -2000, 3000, -1000, 500)
    set test_data [binary format s* {1000 -2000 3000 -1000 500}]
    puts "✓ Test data created: [string length $test_data] bytes"

    # Test energy calculation
    set energy [audio::energy $test_data int16]
    puts "✓ Energy: $energy"

    # Test peak calculation
    set peak [audio::peak $test_data int16]
    puts "✓ Peak: $peak"

    # Test comprehensive analysis
    set analysis [audio::analyze $test_data int16]
    puts "✓ Analysis: $analysis"

    # Test with default format wrapper
    set energy2 [audio::energy_default $test_data]
    puts "✓ Energy (default wrapper): $energy2"

    puts "All tests passed!"

} err]} {
    puts "✗ Error: $err"
    puts $::errorInfo
}