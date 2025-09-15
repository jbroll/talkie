#!/usr/bin/env tclsh
# Comprehensive integration test for all talkie components

package require Tk

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir vosk lib]
lappend auto_path [file join $script_dir audio lib]

puts "=== Talkie Integration Test ==="

# Test 1: PortAudio Package
puts "\n1. Testing PortAudio Package..."
if {[catch {
    package require pa
    pa::init
    if {[info commands Pa_Init] ne ""} {
        Pa_Init
        puts "✓ PortAudio commands registered"
    }

    set devices [pa::list_devices]
    puts "✓ Found [llength $devices] audio devices"

    # Find pulse device
    set pulse_device ""
    foreach device $devices {
        if {[dict get $device name] eq "pulse"} {
            set pulse_device $device
            break
        }
    }

    if {$pulse_device ne ""} {
        puts "✓ Pulse device found: [dict get $pulse_device defaultSampleRate] Hz"
    } else {
        puts "✗ Pulse device not found"
    }

} err]} {
    puts "✗ PortAudio test failed: $err"
    exit 1
}

# Test 2: Audio Processing Package
puts "\n2. Testing Audio Processing Package..."
if {[catch {
    package require audio
    puts "✓ Audio package loaded"

    # Test with sample data
    set test_data [binary format s* {1000 -2000 3000}]
    set energy [audio::energy $test_data int16]
    set peak [audio::peak $test_data int16]

    puts "✓ Energy calculation: $energy"
    puts "✓ Peak calculation: $peak"

} err]} {
    puts "✗ Audio package test failed: $err"
    exit 1
}

# Test 3: Vosk Package
puts "\n3. Testing Vosk Package..."
if {[catch {
    package require vosk
    Vosk_Init
    puts "✓ Vosk initialized"

    vosk::set_log_level -1
    puts "✓ Vosk log level set"

    # Check if vosk::load_model exists
    if {[info commands vosk::load_model] ne ""} {
        puts "✓ vosk::load_model command available"
    } else {
        puts "✗ vosk::load_model command not found"
        puts "Available vosk commands:"
        foreach cmd [info commands vosk::*] {
            puts "  $cmd"
        }
    }

} err]} {
    puts "✗ Vosk test failed: $err"
    exit 1
}

# Test 4: Audio Stream Creation
puts "\n4. Testing Audio Stream Creation..."
if {[catch {
    set stream [pa::open_stream -device "pulse" -rate 44100 -channels 1 -frames 4410 -format int16]
    puts "✓ Audio stream created: $stream"

    # Test stream info
    set info [$stream info]
    puts "✓ Stream info: $info"

    # Clean up
    $stream close
    puts "✓ Stream closed successfully"

} err]} {
    puts "✗ Audio stream test failed: $err"
}

# Test 5: Simple GUI Test
puts "\n5. Testing GUI Components..."
if {[catch {
    wm title . "Integration Test"
    wm geometry . 300x200

    label .status -text "Testing GUI..." -font {Arial 12}
    pack .status -pady 20

    # Test variable display
    set test_energy 0.0
    label .energy -text "Energy: 0.0" -font {Arial 10}
    pack .energy -pady 5

    # Update display
    proc update_display {} {
        global test_energy
        set test_energy [expr {rand() * 10}]
        .energy config -text "Energy: [format "%.1f" $test_energy]"
        after 100 update_display
    }

    update_display

    button .close -text "Close Test" -command {destroy .}
    pack .close -pady 10

    puts "✓ GUI components created"

    # Auto-close after 3 seconds
    after 3000 {destroy .}

} err]} {
    puts "✗ GUI test failed: $err"
}

puts "\n=== Integration Test Complete ==="
puts "All core components appear to be working."
puts "Note: Real-time audio testing requires manual verification."

# Start GUI event loop if window exists
if {[winfo exists .]} {
    vwait 3000  ; # Wait up to 3 seconds or until window closes
}