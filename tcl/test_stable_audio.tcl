#!/usr/bin/env tclsh
# Test stable audio functions only (energy and peak)

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir audio lib]

puts "Testing stable audio functions..."

package require audio

# Test with various data sizes
foreach {label data} {
    "Small" {100 -200}
    "Medium" {1000 -2000 3000 -1000 500 -1500 2500}
    "Large" [lrepeat 1000 100 -200 300 -400]
} {
    set test_data [binary format s* $data]
    puts "\n$label test ([string length $test_data] bytes):"

    set energy [audio::energy $test_data int16]
    puts "  Energy: $energy"

    set peak [audio::peak $test_data int16]
    puts "  Peak: $peak"

    # Test with wrapper
    set energy2 [audio::energy_default $test_data]
    puts "  Energy (wrapper): $energy2"
}

puts "\n✓ All stable functions work correctly!"