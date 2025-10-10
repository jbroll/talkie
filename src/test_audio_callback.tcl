#!/usr/bin/env tclsh
# Test the complete audio callback flow

set script_dir [file dirname [file normalize [info script]]]

# Load all required packages and modules
lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"
lappend auto_path [file join $script_dir vosk lib vosk]
lappend auto_path [file join $script_dir pa lib pa]
lappend auto_path [file join $script_dir audio lib audio]

package require json
package require jbr::unix
package require vosk
package require pa
package require audio

# Load config
source [file join $script_dir config.tcl]
config_load

# Set speech engine to vosk
set ::config(speech_engine) "vosk"

# Mock functions
proc print {args} { puts "  [join $args]" }
proc partial_text {text} { puts "PARTIAL: $text" }
proc final_text {text conf} { puts "FINAL: $text (conf: $conf)" }
proc state_save {val} {}
proc state_load {} { return 0 }
set ::transcribing 0

# Load modules
source [file join $script_dir coprocess.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir engine.tcl]
source [file join $script_dir textproc.tcl]
source [file join $script_dir threshold.tcl]

# Mock uinput
namespace eval uinput {
    proc type {text} {
        puts "UINPUT TYPE: $text"
    }
}

# Initialize threshold
set ::device_sample_rate 16000
threshold::init

# Initialize engine
puts "=== Initializing Engine ==="
if {![::engine::initialize]} {
    puts "ERROR: Engine initialization failed"
    exit 1
}

puts "\n=== Getting Recognizer ==="
set recognizer [::engine::recognizer]
puts "Recognizer: $recognizer"

if {$recognizer eq ""} {
    puts "ERROR: Recognizer is empty!"
    exit 1
}

puts "\n=== Testing Recognizer Methods ==="

# Test reset
puts "\n1. Testing reset..."
$recognizer reset
puts "  ✓ Reset successful"

# Test process
puts "\n2. Testing process..."
set audio_data [binary format s* [lrepeat 1600 0]]
set result [$recognizer process $audio_data]
puts "  Result: $result"

# Parse result
if {$result ne ""} {
    set result_dict [json::json2dict $result]
    if {[dict exists $result_dict partial]} {
        puts "  ✓ Got partial result: [dict get $result_dict partial]"
    }
}

# Test final-result
puts "\n3. Testing final-result..."
set result [$recognizer final-result]
puts "  Result: $result"

if {$result ne ""} {
    set result_dict [json::json2dict $result]
    if {[dict exists $result_dict alternatives]} {
        set text [lindex [dict get $result_dict alternatives] 0]
        puts "  ✓ Got final result: [dict get $text text]"
    }
}

puts "\n=== All Tests Passed ==="
