#!/usr/bin/env tclsh
# Minimal test to debug audio package segfault

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir audio lib]

puts "=== Audio Package Debug Test ==="

puts "Step 1: Loading package..."
if {[catch {
    package require audio
    puts "✓ Package loaded successfully"
} err]} {
    puts "✗ Package load failed: $err"
    exit 1
}

puts "Step 2: Creating minimal test data..."
set test_data [binary format s* {100 -200}]
puts "✓ Created [string length $test_data] bytes"

puts "Step 3: Testing energy function..."
if {[catch {
    set energy [audio::energy $test_data int16]
    puts "✓ Energy result: $energy"
} err]} {
    puts "✗ Energy function failed: $err"
    puts $::errorInfo
    exit 1
}

puts "Step 4: Testing peak function..."
if {[catch {
    set peak [audio::peak $test_data int16]
    puts "✓ Peak result: $peak"
} err]} {
    puts "✗ Peak function failed: $err"
    puts $::errorInfo
    exit 1
}

puts "=== Test completed successfully ==="