#!/usr/bin/env tclsh
# Test the complete transcription flow

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"
lappend auto_path [file join $script_dir vosk lib vosk]
lappend auto_path [file join $script_dir pa lib pa]
lappend auto_path [file join $script_dir audio lib audio]

package require json
package require jbr::unix
package require vosk
package require pa
package require audio

# Load config and modules
source [file join $script_dir config.tcl]
source [file join $script_dir textproc.tcl]
source [file join $script_dir threshold.tcl]

config_load
set ::config(speech_engine) "vosk"

# Mock functions
proc print {args} { puts "[join $args]" }
proc partial_text {text} {
    if {$text ne ""} {
        puts "  PARTIAL: '$text'"
    }
}
proc final_text {text conf} {
    puts "  FINAL: '$text' (confidence: $conf)"
}
proc state_save {val} {}
proc state_load {} { return 0 }

namespace eval uinput {
    proc type {text} {
        puts "  UINPUT: '$text'"
    }
}

# Load engine
source [file join $script_dir coprocess.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir engine.tcl]
source [file join $script_dir audio.tcl]

puts "=== Testing Complete Transcription Flow ==="

# Initialize device
::audio::refresh_devices
puts "\nDevice sample rate: $::device_sample_rate"

# Initialize engine
puts "\n1. Initializing audio system..."
if {![::audio::initialize]} {
    puts "ERROR: Audio initialization failed"
    exit 1
}
puts "✓ Audio system initialized"

# Check recognizer
set rec [::engine::recognizer]
puts "\n2. Recognizer: '$rec'"
if {$rec eq ""} {
    puts "ERROR: Recognizer is empty!"
    exit 1
}

# Start transcription
puts "\n3. Starting transcription..."
if {[::audio::start_transcription]} {
    puts "✓ Transcription started"
    puts "  transcribing = $::transcribing"
} else {
    puts "ERROR: Failed to start transcription"
    exit 1
}

# Simulate audio with speech
puts "\n4. Simulating audio chunks..."
for {set i 0} {$i < 10} {incr i} {
    # Generate fake audio with some energy
    set amplitude [expr {1000 + $i * 500}]
    set audio [binary format s* [lrepeat 4410 $amplitude]]

    # Call audio callback
    ::audio::audio_callback "test" [expr {$i * 0.1}] $audio
}

puts "\n5. Waiting for silence timeout..."
::audio::audio_callback "test" 2.0 [binary format s* [lrepeat 4410 0]]

puts "\n=== Test Complete ==="
puts "If you see FINAL output above, STT is working!"
