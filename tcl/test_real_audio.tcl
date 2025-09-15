#!/usr/bin/env tclsh
# Test real audio input and energy calculation

package require Tk

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir audio lib]

package require pa
pa::init
Pa_Init

package require audio

# Create GUI
wm title . "Real Audio Test"
wm geometry . 400x300

label .title -text "Testing Real Audio Input" -font {Arial 14 bold}
pack .title -pady 10

# Energy display
frame .energy_frame
pack .energy_frame -pady 10

label .energy_frame.label -text "Audio Energy:" -font {Arial 12}
pack .energy_frame.label -side left

label .energy_frame.value -text "0.0" -font {Arial 14 bold} -bg white -relief sunken -width 10
pack .energy_frame.value -side left -padx 10

# Callback counter
label .callbacks -text "Callbacks: 0" -font {Arial 10}
pack .callbacks -pady 5

# Control buttons
button .start -text "Start Audio" -command start_audio -bg green -fg white
pack .start -pady 5

button .stop -text "Stop Audio" -command stop_audio -bg red -fg white
pack .stop -pady 5

# Status
label .status -text "Click Start to begin" -font {Arial 10}
pack .status -pady 10

# Variables
set stream ""
set callback_count 0
set max_energy 0.0
set running 0

# Audio callback
proc audio_callback {stream_name timestamp data} {
    global callback_count max_energy

    incr callback_count

    # Calculate energy
    set energy [audio::energy $data int16]

    if {$energy > $max_energy} {
        set max_energy $energy
    }

    # Update UI in main thread
    after idle [list update_display $energy]
}

# Update display
proc update_display {energy} {
    global callback_count max_energy

    .energy_frame.value config -text [format "%.2f" $energy]
    .callbacks config -text "Callbacks: $callback_count (max: [format "%.2f" $max_energy])"

    # Color coding
    if {$energy > 2.0} {
        .energy_frame.value config -bg "#4CAF50" -fg white
    } elseif {$energy > 0.5} {
        .energy_frame.value config -bg "#FF9800" -fg white
    } else {
        .energy_frame.value config -bg "#f44336" -fg white
    }
}

# Start audio
proc start_audio {} {
    global stream running

    if {$running} return

    set running 1
    .status config -text "Starting audio stream..."

    if {[catch {
        set stream [pa::open_stream \
            -device "pulse" \
            -rate 44100 \
            -channels 1 \
            -frames 4410 \
            -format int16 \
            -callback audio_callback]

        $stream start
        .status config -text "Audio streaming... (speak into microphone)"
        .start config -state disabled
        .stop config -state normal

    } err]} {
        .status config -text "Error: $err"
        set running 0
    }
}

# Stop audio
proc stop_audio {} {
    global stream running

    set running 0

    if {$stream ne ""} {
        if {[catch {
            $stream stop
            $stream close
        } err]} {
            .status config -text "Stop error: $err"
        }
        set stream ""
    }

    .status config -text "Audio stopped"
    .start config -state normal
    .stop config -state disabled
}

# Auto start after 1 second
after 1000 start_audio

# Auto stop after 10 seconds
after 10000 stop_audio

# Close after 12 seconds
after 12000 {destroy .}

puts "Real audio test starting..."
puts "Window will auto-start audio and close in 12 seconds"