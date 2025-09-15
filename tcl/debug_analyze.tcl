#!/usr/bin/env tclsh
# Test audio::analyze function specifically

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir audio lib]

puts "Testing audio::analyze function..."

package require audio

set test_data [binary format s* {100 -200}]
puts "Created test data: [string length $test_data] bytes"

puts "Testing analyze function..."
if {[catch {
    set result [audio::analyze $test_data int16]
    puts "✓ Analyze result: $result"
} err]} {
    puts "✗ Analyze failed: $err"
    puts $::errorInfo
}

puts "Done."