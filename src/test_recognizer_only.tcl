#!/usr/bin/env tclsh
# Minimal test of recognizer functionality

set script_dir [file dirname [file normalize [info script]]]

# Load required packages
lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"
lappend auto_path [file join $script_dir vosk lib vosk]

package require json
package require vosk

# Mock config
array set ::config {
    speech_engine vosk
    vosk_modelfile vosk-model-en-us-0.22-lgraph
}
set ::device_sample_rate 16000

# Mock functions
proc print {args} { puts "  [join $args]" }
proc get_model_path {modelfile} {
    return [file join [file dirname $::script_dir] models vosk $modelfile]
}

# Load modules
source [file join $script_dir coprocess.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir engine.tcl]

puts "=== Testing Recognizer ==="

# Initialize
if {![::engine::initialize]} {
    puts "ERROR: Failed to initialize"
    exit 1
}

set rec [::engine::recognizer]
puts "Recognizer: '$rec'"

if {$rec eq ""} {
    puts "ERROR: Recognizer is empty"
    exit 1
}

puts "\n✓ Recognizer initialized: $rec"

# Test methods
puts "\nTesting methods..."

puts "  1. reset"
$rec reset
puts "    ✓ reset works"

puts "  2. process (silence)"
set silence [binary format s* [lrepeat 1600 0]]
set result [$rec process $silence]
puts "    Result: [string range $result 0 80]..."
if {$result eq ""} {
    puts "    ✗ ERROR: process returned empty!"
    exit 1
}
puts "    ✓ process works"

puts "  3. final-result"
set result [$rec final-result]
puts "    Result: [string range $result 0 80]..."
if {$result eq ""} {
    puts "    ✗ ERROR: final-result returned empty!"
    exit 1
}
puts "    ✓ final-result works"

puts "\n=== All Tests Passed ==="
puts "The recognizer is working correctly."
