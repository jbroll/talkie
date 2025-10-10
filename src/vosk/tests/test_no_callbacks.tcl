#!/usr/bin/env tclsh
# test_no_callbacks.tcl - Test integration without callbacks

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]
set auto_path [linsert $auto_path 0 [file join [pwd] ../pa lib]]

puts "Testing integration without callbacks..."

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

# Create recognizer WITHOUT callback
set recognizer [$model create_recognizer -rate 16000]
puts "✓ Recognizer created: $recognizer"

# Simple audio callback without invoking speech recognition
proc simple_audio_callback {stream timestamp data} {
    global audio_count
    incr audio_count
    if {$audio_count % 50 == 0} {
        puts "Processed $audio_count audio buffers..."
    }
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

# Create PortAudio stream with simple callback
set stream [pa::open_stream \
    -device default \
    -rate 16000 \
    -channels 1 \
    -frames 1024 \
    -format int16 \
    -callback simple_audio_callback]

puts "✓ PortAudio stream created: $stream"

# Initialize counter
set audio_count 0

puts "\n🎤 Starting simple audio capture..."
$stream start

# Let it run for 5 seconds
after 5000 {
    puts "\n⏹ Stopping after 5 seconds..."
    $stream stop
    puts "✓ Stream stopped"

    puts "\n📊 Statistics:"
    puts "Audio buffers processed: $audio_count"

    puts "\n🧹 Cleaning up..."
    $stream close
    $recognizer close
    $model close

    puts "✅ Test completed successfully!"
    exit 0
}

puts "Event loop running..."
vwait forever