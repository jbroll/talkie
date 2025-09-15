#!/usr/bin/env tclsh
# Test audio callback and UI update flow

package require Tk

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir audio lib]

# Load packages
package require pa
pa::init
Pa_Init

package require audio

puts "=== Testing Audio Callback and UI Flow ==="

# Create simple GUI
wm title . "Audio Flow Test"
wm geometry . 400x300

label .status -text "Testing audio callback flow..." -font {Arial 12}
pack .status -pady 10

label .energy -text "Energy: --" -font {Arial 14} -bg white -relief sunken
pack .energy -pady 10

label .callback_count -text "Callbacks: 0" -font {Arial 10}
pack .callback_count -pady 5

button .start -text "Start Audio Test" -command start_test
pack .start -pady 10

button .stop -text "Stop Test" -command stop_test
pack .stop -pady 10

# Global variables
set audio_stream ""
set callback_count 0
set current_energy 0.0

# Audio callback procedure
proc audio_callback {stream_name timestamp data} {
    global callback_count current_energy

    incr callback_count

    # Calculate energy using C function
    if {[catch {
        set current_energy [audio::energy $data int16]
    } err]} {
        puts "Energy calculation error: $err"
        set current_energy 0.0
    }

    # Update UI (should be done in main thread)
    after idle update_ui
}

# UI update procedure
proc update_ui {} {
    global callback_count current_energy

    .energy config -text "Energy: [format "%.2f" $current_energy]"
    .callback_count config -text "Callbacks: $callback_count"

    # Color code energy level
    if {$current_energy > 5.0} {
        .energy config -bg "#4CAF50" -fg white
    } elseif {$current_energy > 2.0} {
        .energy config -bg "#FF9800" -fg white
    } else {
        .energy config -bg "#f44336" -fg white
    }
}

# Start test
proc start_test {} {
    global audio_stream

    puts "Starting audio test..."
    .status config -text "Audio test running..."

    if {[catch {
        set audio_stream [pa::open_stream \
            -device "pulse" \
            -rate 44100 \
            -channels 1 \
            -frames 4410 \
            -format int16 \
            -callback audio_callback]

        $audio_stream start
        puts "✓ Audio stream started: $audio_stream"

    } err]} {
        puts "✗ Error starting audio: $err"
        .status config -text "Error: $err"
    }
}

# Stop test
proc stop_test {} {
    global audio_stream

    if {$audio_stream ne ""} {
        if {[catch {
            $audio_stream stop
            $audio_stream close
            puts "✓ Audio stream stopped"
        } err]} {
            puts "Warning: $err"
        }
        set audio_stream ""
    }

    .status config -text "Audio test stopped"
}

# Auto-start test after 1 second
after 1000 start_test

# Auto-stop after 10 seconds
after 10000 stop_test

# Close window after 12 seconds
after 12000 {destroy .}

puts "Starting GUI test - window will auto-close in 12 seconds"
puts "Speak into microphone to test energy detection"