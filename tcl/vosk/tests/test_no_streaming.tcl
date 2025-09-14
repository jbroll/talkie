#!/usr/bin/env tclsh
# test_no_streaming.tcl - Test without starting audio stream

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]
set auto_path [linsert $auto_path 0 [file join [pwd] ../pa lib]]

puts "Testing without audio streaming..."

# Load packages
package require pa
package require vosk

# Initialize both systems
Pa_Init
Vosk_Init
puts "✓ PortAudio and Vosk initialized"

# Load model
set model_path "../../models/vosk-model-en-us-0.22-lgraph"
set model [vosk::load_model -path $model_path]
puts "✓ Model loaded: $model"

# Create recognizer
set recognizer [$model create_recognizer -rate 16000]
puts "✓ Recognizer created: $recognizer"

# Audio callback (but won't be called)
proc audio_callback {stream timestamp data} {
    puts "This should never be called"
}

# List available devices
puts "\nAvailable audio devices:"
foreach device [pa::list_devices] {
    dict with device {
        if {$maxInputChannels > 0} {
            puts "  $index: $name (channels: $maxInputChannels)"
        }
    }
}

# Create PortAudio stream but DON'T START IT
set stream [pa::open_stream \
    -device default \
    -rate 16000 \
    -channels 1 \
    -frames 1024 \
    -format int16 \
    -callback audio_callback]

puts "✓ PortAudio stream created (not started): $stream"

# Wait a bit then clean up
after 2000 {
    puts "\n🧹 Cleaning up without starting stream..."
    $stream close
    $recognizer close
    $model close

    puts "✅ Test completed successfully without streaming!"
    exit 0
}

puts "Waiting 2 seconds..."
vwait forever