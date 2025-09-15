#!/usr/bin/env tclsh
# Test energy display with real audio stream

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

puts "=== Testing Energy Display ==="

# Create GUI
wm title . "Energy Display Test"
wm geometry . 300x200

label .title -text "Real-time Energy Display" -font {Arial 12 bold}
pack .title -pady 10

label .energy -text "Energy: --" -font {Arial 14} -bg white -relief sunken -width 20
pack .energy -pady 10

label .callbacks -text "Callbacks: 0" -font {Arial 10}
pack .callbacks -pady 5

button .start -text "Start Audio" -command start_audio -bg "#4CAF50" -fg white
pack .start -pady 5

button .stop -text "Stop Audio" -command stop_audio -bg "#f44336" -fg white
pack .stop -pady 5

# Variables
set audio_stream ""
set callback_count 0
set current_energy 0.0
set running false

# Audio callback
proc audio_callback {stream_name timestamp data} {
    global callback_count current_energy

    incr callback_count

    # Calculate energy with C function
    if {[catch {
        set current_energy [audio::energy $data int16]
    } err]} {
        puts "Energy calc error: $err"
        set current_energy 0.0
    }

    # Trigger UI update in main thread
    after idle update_display
}

# Update display
proc update_display {} {
    global callback_count current_energy

    .energy config -text "Energy: [format "%.2f" $current_energy]"
    .callbacks config -text "Callbacks: $callback_count"

    # Color coding
    if {$current_energy > 5.0} {
        .energy config -bg "#4CAF50" -fg white
    } elseif {$current_energy > 1.0} {
        .energy config -bg "#FF9800" -fg white
    } else {
        .energy config -bg "#f44336" -fg white
    }
}

# Start audio
proc start_audio {} {
    global audio_stream running

    set running true
    puts "Starting audio stream..."

    if {[catch {
        set audio_stream [pa::open_stream \
            -device "pulse" \
            -rate 44100 \
            -channels 1 \
            -frames 4410 \
            -format int16 \
            -callback audio_callback]

        $audio_stream start
        puts "✓ Audio stream started"
        .start config -state disabled
        .stop config -state normal

    } err]} {
        puts "✗ Error: $err"
        set running false
    }
}

# Stop audio
proc stop_audio {} {
    global audio_stream running

    set running false

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

    .start config -state normal
    .stop config -state disabled
}

# Cleanup on exit
proc cleanup {} {
    global running
    if {$running} {
        stop_audio
    }
    destroy .
}

wm protocol . WM_DELETE_WINDOW cleanup
bind . <KeyPress-Escape> cleanup

puts "Starting energy display test..."
puts "Click 'Start Audio' to begin real-time energy monitoring"
puts "Speak into microphone to see energy levels change"