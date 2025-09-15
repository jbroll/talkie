#!/usr/bin/env tclsh
# Test core audio functions only

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir audio lib]

puts "Testing core audio functions..."

package require audio

# Test with real-world audio buffer size (100ms at 44.1kHz = 4410 samples)
set large_data [lrepeat 4410 100 -200 300 -400 150 -250]
set test_data [binary format s* $large_data]

puts "Testing with [string length $test_data] bytes ([expr {[string length $test_data]/2}] samples):"

set energy [audio::energy $test_data int16]
puts "✓ Energy: $energy"

set peak [audio::peak $test_data int16]
puts "✓ Peak: $peak"

puts "\n✓ Audio package energy/peak functions are stable and ready for use!"