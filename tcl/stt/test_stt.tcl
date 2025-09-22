#!/usr/bin/env tclsh
# Test script for unified STT system

# Set up the path for our packages
set auto_path [linsert $auto_path 0 [file join [pwd] tcl stt lib]]

puts "Testing unified STT system..."
puts "Audio file: [file join [pwd] test_audio voice-sample.wav]"
puts "Vosk model: [file join [pwd] models vosk vosk-model-en-us-0.22-lgraph]"

# Test Vosk first
puts "\n=== Testing Vosk Integration ==="

# Try to load and build the packages
if {[catch {
    # Set up environment
    set env(LD_LIBRARY_PATH) "$env(HOME)/.local/lib:$env(LD_LIBRARY_PATH)"

    # Build and load the packages
    puts "Building STT core package..."
    cd tcl/stt
    package require stt

    puts "Building Vosk package..."
    package require vosk_engine

    puts "Packages loaded successfully!"

} err]} {
    puts "Error loading packages: $err"
    puts "Trying to build packages manually..."

    # Try building with critcl directly
    cd tcl/stt

    puts "Building stt.tcl..."
    if {[catch {exec tclsh stt.tcl} build_err]} {
        puts "stt.tcl build error: $build_err"
    }

    puts "Building vosk.tcl..."
    if {[catch {exec tclsh vosk.tcl} build_err]} {
        puts "vosk.tcl build error: $build_err"
    }
}

puts "Test completed."