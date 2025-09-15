#!/usr/bin/env tclsh
# Debug audio input to check for noise issues

puts "🎤 Audio Input Debug Test"
puts [string repeat "-" 40]

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]

# Load PortAudio
package require pa
pa::init
if {[info commands Pa_Init] ne ""} {
    Pa_Init
}

# Get devices and find pulse
set devices [pa::list_devices]
set pulse_device ""
set pulse_index -1

foreach device $devices {
    dict with device {
        if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
            if {[string match -nocase "*pulse*" $name]} {
                set pulse_device $name
                set pulse_index $index
                break
            }
        }
    }
}

if {$pulse_device eq ""} {
    puts "❌ No pulse device found!"
    exit 1
}

puts "✅ Found pulse device: $pulse_device (ID: $pulse_index)"

# Test basic stream creation
puts "\n🔧 Testing stream creation..."
if {[catch {
    set stream [pa::open_stream \
        -device $pulse_device \
        -rate 16000 \
        -channels 1 \
        -frames 512 \
        -format int16]

    puts "✅ Stream created successfully"
    puts "Stream info: [$stream info]"

    # Test starting stream briefly
    $stream start
    puts "✅ Stream started"

    after 1000  ;# Let it run for 1 second

    $stream stop
    puts "✅ Stream stopped"

    set stats [$stream stats]
    puts "Stream stats: $stats"

    $stream close
    puts "✅ Stream closed"

} err]} {
    puts "❌ Stream error: $err"
}

# Test with callback to check actual audio data
puts "\n🔊 Testing audio data reception..."
set audio_samples 0
set max_amplitude 0

proc audio_callback {stream_name timestamp data} {
    global audio_samples max_amplitude

    incr audio_samples

    # Convert binary data to check amplitude
    binary scan $data s* samples
    foreach sample $samples {
        set abs_sample [expr {abs($sample)}]
        if {$abs_sample > $max_amplitude} {
            set max_amplitude $abs_sample
        }
    }

    if {$audio_samples <= 10} {
        puts "Callback $audio_samples: [string length $data] bytes, max amp: $max_amplitude"
    }
}

if {[catch {
    set stream [pa::open_stream \
        -device $pulse_device \
        -rate 16000 \
        -channels 1 \
        -frames 256 \
        -format int16 \
        -callback audio_callback]

    $stream start
    puts "✅ Callback stream started - listening for 3 seconds..."

    after 3000 {
        set ::done 1
    }

    vwait ::done

    $stream stop
    $stream close

    puts "\n📊 Audio Analysis Results:"
    puts "   Total callbacks: $audio_samples"
    puts "   Max amplitude: $max_amplitude (out of 32767)"

    if {$audio_samples == 0} {
        puts "❌ No audio callbacks received - audio not working"
    } elseif {$max_amplitude < 100} {
        puts "⚠️  Very low audio levels - might be noise or no input"
    } elseif {$max_amplitude > 10000} {
        puts "✅ Good audio levels detected"
    } else {
        puts "✅ Audio detected but levels are low"
    }

} err]} {
    puts "❌ Callback test error: $err"
}

puts "\n🎯 Debug test complete!"