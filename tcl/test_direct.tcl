#!/usr/bin/env tclsh
# test_direct.tcl - Direct test of already-built packages

# Test if we can load the pre-built packages directly
puts "Testing pre-built packages..."

# Setup path to the lib directories
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir vosk lib]

# Test PortAudio package
puts "Testing PortAudio..."
if {[catch {
    package require pa
    puts "✓ PortAudio package loaded: [package present pa]"

    # Test what commands are available
    set pa_commands [info commands pa::*]
    puts "Available pa:: commands: $pa_commands"

    set Pa_commands [info commands Pa_*]
    puts "Available Pa_ commands: $Pa_commands"

    # Try initialize
    if {[info commands pa::init] ne ""} {
        set result [pa::init]
        puts "✓ pa::init result: $result"
    } else {
        puts "! pa::init command not found"
    }

} err]} {
    puts "✗ PortAudio error: $err"
}

puts ""

# Test Vosk package
puts "Testing Vosk..."
if {[catch {
    package require vosk
    puts "✓ Vosk package loaded: [package present vosk]"

    # Test what commands are available
    set vosk_commands [info commands vosk::*]
    puts "Available vosk:: commands: $vosk_commands"

    set Vosk_commands [info commands Vosk_*]
    puts "Available Vosk_ commands: $Vosk_commands"

} err]} {
    puts "✗ Vosk error: $err"
}

puts "\nDone."