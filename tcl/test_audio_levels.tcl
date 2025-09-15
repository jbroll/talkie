#!/usr/bin/env tclsh
# Test audio level calculation with different sample rates

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]

package require pa
pa::init
if {[info commands Pa_Init] ne ""} {
    Pa_Init
}

puts "Testing audio level calculation..."

# Get pulse device info
set devices [pa::list_devices]
foreach device $devices {
    if {[dict get $device name] eq "pulse"} {
        set pulse_rate [dict get $device defaultSampleRate]
        puts "Pulse device sample rate: $pulse_rate Hz"

        # Calculate 100ms buffer size
        set frames_100ms [expr {int($pulse_rate * 0.1)}]
        puts "Buffer size for 100ms: $frames_100ms frames"

        # Create stream with proper config
        puts "Creating audio stream..."
        set stream [pa::open_stream \
            -device "pulse" \
            -rate $pulse_rate \
            -channels 1 \
            -frames $frames_100ms \
            -format int16 \
            -callback test_audio_callback]

        puts "✓ Stream created: $stream"
        puts "Starting audio capture for 5 seconds..."

        $stream start

        # Wait and show energy levels
        for {set i 0} {$i < 50} {incr i} {
            after 100
            update
        }

        $stream stop
        $stream close
        puts "✓ Test completed"
        break
    }
}

proc test_audio_callback {stream_name timestamp data} {
    # Calculate RMS energy like in the main app
    binary scan $data s* samples
    set sum_squares 0
    set num_samples [llength $samples]

    if {$num_samples > 0} {
        foreach sample $samples {
            set sum_squares [expr {$sum_squares + ($sample * $sample)}]
        }
        set rms [expr {sqrt($sum_squares / double($num_samples))}]
        set energy [expr {$rms / 32768.0 * 100.0}]

        puts "Audio energy: [format "%.2f" $energy]% (${num_samples} samples)"
    }
}