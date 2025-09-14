#!/usr/bin/env tclsh
# test_vosk_integration.tcl - Test Vosk speech recognition with PortAudio streaming

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]
set auto_path [linsert $auto_path 0 [file join [pwd] ../pa lib]]

# Load both packages
package require pa
package require vosk

# Initialize both systems
Pa_Init
Vosk_Init
puts "✓ PortAudio and Vosk initialized"

# Configuration
set model_path "../../models/vosk-model-en-us-0.22-lgraph"
set sample_rate 16000
set channels 1
set frames_per_buffer 1024

# Check if model path exists
if {![file exists $model_path]} {
    puts "✗ Vosk model not found at: $model_path"
    puts "Please download a Vosk model and update the model_path variable"
    exit 1
}

# Load Vosk model
puts "Loading Vosk model from: $model_path"
set model [vosk::load_model -path $model_path]
puts "✓ Vosk model loaded: $model"

# Create Vosk recognizer with callback
proc speech_callback {recognizer json_result is_final} {
    global recognition_count
    incr recognition_count

    puts "=== Speech Recognition Result #$recognition_count ==="
    puts "Recognizer: $recognizer"
    puts "Is Final: $is_final"
    puts "JSON: $json_result"

    # Parse JSON to extract text and confidence
    if {$json_result ne ""} {
        # Simple JSON parsing for demonstration
        if {[regexp {"text"\s*:\s*"([^"]*)"} $json_result -> text]} {
            if {$text ne ""} {
                puts "Text: '$text'"

                # Extract confidence if available
                if {[regexp {"confidence"\s*:\s*([0-9.]+)} $json_result -> confidence]} {
                    puts "Confidence: $confidence"
                }
            }
        }
    }
    puts "=============================================="
}

set recognizer [$model create_recognizer -rate $sample_rate -callback speech_callback -alternatives 1]
puts "✓ Vosk recognizer created: $recognizer"

# Audio callback that feeds audio data to Vosk recognizer
proc audio_callback {stream timestamp data} {
    global recognizer audio_buffer_count
    incr audio_buffer_count

    # Show periodic status
    if {$audio_buffer_count % 50 == 0} {
        puts "Processed $audio_buffer_count audio buffers..."
    }

    # Feed audio data directly to Vosk recognizer
    # The data from PortAudio is already in the correct format (16-bit PCM)
    try {
        $recognizer process $data
    } on error {err} {
        puts "Error processing audio: $err"
    }
}

# List available audio devices
puts "\nAvailable audio devices:"
foreach device [pa::list_devices] {
    dict with device {
        puts "  $index: $name (channels: $maxInputChannels, rate: $defaultSampleRate)"
    }
}

# Find a suitable input device (prefer USB or containing "input")
set device_name "default"
foreach device [pa::list_devices] {
    dict with device {
        if {$maxInputChannels > 0 && ([string match -nocase "*usb*" $name] || [string match -nocase "*input*" $name])} {
            set device_name $name
            puts "Selected device: $device_name"
            break
        }
    }
}

# Create PortAudio stream
puts "\nCreating PortAudio stream..."
set stream [pa::open_stream \
    -device $device_name \
    -rate $sample_rate \
    -channels $channels \
    -frames $frames_per_buffer \
    -format int16 \
    -callback audio_callback]

puts "✓ PortAudio stream created: $stream"
puts "Stream info: [$stream info]"

# Initialize counters
set recognition_count 0
set audio_buffer_count 0

# Start audio capture and speech recognition
puts "\n🎤 Starting audio capture and speech recognition..."
puts "Speak into your microphone. The system will transcribe your speech in real-time."
puts "Press Ctrl+C to stop or wait 30 seconds for automatic stop.\n"

$stream start

# Let it run for 30 seconds
after 30000 {
    puts "\n⏹ Stopping recording after 30 seconds..."

    # Stop audio stream
    $stream stop
    puts "✓ PortAudio stream stopped"

    # Get final result from recognizer
    set final_result [$recognizer final_result]
    puts "Final result: $final_result"

    # Show statistics
    puts "\n📊 Statistics:"
    puts "Audio buffers processed: $audio_buffer_count"
    puts "Speech recognition events: $recognition_count"
    puts "Stream stats: [$stream stats]"

    # Cleanup
    puts "\n🧹 Cleaning up..."
    $stream close
    $recognizer close
    $model close

    puts "✅ Test completed successfully!"
    exit 0
}

# Keep event loop running
puts "Event loop running... (use vwait to process audio callbacks)"
vwait forever