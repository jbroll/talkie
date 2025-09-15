#!/usr/bin/env tclsh
# Test complete pipeline: PA device → audio callbacks → energy calculation → UI updates

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

puts "=== Testing Complete Audio Pipeline ==="

# Create GUI to verify UI updates
wm title . "Complete Pipeline Test"
wm geometry . 500x400

label .title -text "Testing PA Device → Energy → UI Pipeline" -font {Arial 14 bold}
pack .title -pady 10

# Status display
label .status -text "Initializing..." -font {Arial 12}
pack .status -pady 5

# Energy display
frame .energy_frame
pack .energy_frame -pady 10

label .energy_frame.label -text "Real-time Energy:" -font {Arial 12}
pack .energy_frame.label -side left

label .energy_frame.value -text "0.0" -font {Arial 16 bold} -bg white -relief sunken -width 12
pack .energy_frame.value -side left -padx 10

# Statistics
label .stats -text "Callbacks: 0 | Min: 0.0 | Max: 0.0 | Avg: 0.0" -font {Arial 10}
pack .stats -pady 5

# Energy history (text display)
label .history_label -text "Energy History (last 10 values):" -font {Arial 10}
pack .history_label -anchor w -padx 10

text .history -height 8 -width 60 -font {Courier 10}
pack .history -pady 5 -padx 10 -fill x

scrollbar .scroll -command ".history yview"
.history config -yscrollcommand ".scroll set"

# Control buttons
button .start -text "Start Real Audio Test" -command start_test -bg "#4CAF50" -fg white
pack .start -pady 5

button .stop -text "Stop Test" -command stop_test -bg "#f44336" -fg white
pack .stop -pady 5

# Global variables
set audio_stream ""
set callback_count 0
set energy_values {}
set energy_sum 0.0
set energy_min 999.0
set energy_max 0.0
set running false

# Audio callback - this runs in PortAudio thread context
proc audio_callback {stream_name timestamp data} {
    global callback_count energy_values energy_sum energy_min energy_max

    incr callback_count

    # CRITICAL TEST: Calculate energy from real PA buffer data
    if {[catch {
        set energy [audio::energy $data int16]
    } err]} {
        puts "ERROR in energy calculation: $err"
        set energy 0.0
    }

    # Track statistics
    set energy_sum [expr {$energy_sum + $energy}]
    if {$energy < $energy_min} { set energy_min $energy }
    if {$energy > $energy_max} { set energy_max $energy }

    # Keep last 10 values
    lappend energy_values $energy
    if {[llength $energy_values] > 10} {
        set energy_values [lrange $energy_values 1 end]
    }

    # CRITICAL TEST: Update UI from callback data
    after idle [list update_ui_from_callback $energy $timestamp]
}

# UI update from callback data - this runs in main UI thread
proc update_ui_from_callback {energy timestamp} {
    global callback_count energy_values energy_sum energy_min energy_max

    # Update energy display
    .energy_frame.value config -text [format "%.3f" $energy]

    # Color coding based on energy level
    if {$energy > 2.0} {
        .energy_frame.value config -bg "#4CAF50" -fg white  ;# Green - good signal
    } elseif {$energy > 0.5} {
        .energy_frame.value config -bg "#FF9800" -fg white  ;# Orange - medium
    } elseif {$energy > 0.0} {
        .energy_frame.value config -bg "#2196F3" -fg white  ;# Blue - low signal
    } else {
        .energy_frame.value config -bg "#f44336" -fg white  ;# Red - no signal
    }

    # Update statistics
    set avg [expr {$callback_count > 0 ? $energy_sum / $callback_count : 0.0}]
    .stats config -text [format "Callbacks: %d | Min: %.3f | Max: %.3f | Avg: %.3f" \
        $callback_count $energy_min $energy_max $avg]

    # Update energy history
    .history config -state normal
    .history insert end [format "%.3f  " $energy]
    if {[llength $energy_values] == 10} {
        .history insert end "\n"
    }
    .history see end
    .history config -state disabled

    # Log every 50th callback to console
    if {$callback_count % 50 == 0} {
        puts [format "Callback %d: Energy %.3f (timestamp %.3f)" $callback_count $energy $timestamp]
    }
}

# Start the audio test
proc start_test {} {
    global audio_stream running callback_count energy_values energy_sum energy_min energy_max

    if {$running} return

    # Reset statistics
    set callback_count 0
    set energy_values {}
    set energy_sum 0.0
    set energy_min 999.0
    set energy_max 0.0

    .history config -state normal
    .history delete 1.0 end
    .history config -state disabled

    set running true
    .status config -text "Testing PA device → audio callbacks → energy calculation..."

    puts "Starting PA audio stream with real-time energy calculation..."

    if {[catch {
        # CRITICAL: Create real audio stream with callback
        set audio_stream [pa::open_stream \
            -device "pulse" \
            -rate 44100 \
            -channels 1 \
            -frames 4410 \
            -format int16 \
            -callback audio_callback]

        puts "✓ Audio stream created: $audio_stream"

        # CRITICAL: Start actual audio capture
        $audio_stream start
        puts "✓ Audio stream started - real microphone data flowing"

        .status config -text "ACTIVE: Real audio data → energy calculation → UI updates"
        .start config -state disabled
        .stop config -state normal

    } err]} {
        puts "✗ ERROR starting audio stream: $err"
        .status config -text "ERROR: $err"
        set running false
    }
}

# Stop the test
proc stop_test {} {
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

    .status config -text "Test stopped - no audio data flowing"
    .start config -state normal
    .stop config -state disabled
}

# Cleanup
proc cleanup {} {
    global running
    if {$running} {
        stop_test
    }
    destroy .
}

wm protocol . WM_DELETE_WINDOW cleanup

puts "\nThis test verifies the complete audio pipeline:"
puts "1. PA device captures real microphone data"
puts "2. Audio callbacks receive buffer data"
puts "3. C-level energy calculation processes buffers"
puts "4. UI updates in real-time with energy values"
puts "\nClick 'Start Real Audio Test' and speak into microphone"
puts "You should see:"
puts "- Background noise: 0.0-2.0 energy levels"
puts "- Voice input: 2.0+ energy levels"
puts "- Real-time updates every 100ms"