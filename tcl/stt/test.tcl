#!/usr/bin/env tclsh

# Unified STT Engine Test
# Tests either Vosk or Sherpa-ONNX engines with the unified STT framework

proc usage {} {
    puts "Usage: $::argv0 <engine> \[model_path\]"
    puts ""
    puts "Engines:"
    puts "  vosk       - Test Vosk engine"
    puts "  sherpa     - Test Sherpa-ONNX engine"
    puts ""
    puts "Examples:"
    puts "  $::argv0 vosk"
    puts "  $::argv0 sherpa"
    puts "  $::argv0 vosk ../models/vosk/custom-model"
    exit 1
}

if {$argc < 1} {
    usage
}

set engine [lindex $argv 0]
set custom_model_path [lindex $argv 1]

# Set library paths
lappend auto_path lib

# Ensure Sherpa-ONNX libraries are found
if {[info exists env(LD_LIBRARY_PATH)]} {
    set env(LD_LIBRARY_PATH) "$env(HOME)/.local/lib:$env(LD_LIBRARY_PATH)"
} else {
    set env(LD_LIBRARY_PATH) "$env(HOME)/.local/lib"
}

puts "=== STT Engine Test ==="
puts "Engine: $engine"

# Configure engine-specific settings
switch $engine {
    "vosk" {
        set package_name "vosk"
        set create_cmd "create_vosk_model"
        set default_model "../../models/vosk/vosk-model-small-en-us-0.15"
    }
    "sherpa" {
        set package_name "sherpa_onnx"
        set create_cmd "create_sherpa_model"
        set default_model "../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26"
    }
    default {
        puts "✗ Unknown engine: $engine"
        usage
    }
}

# Use custom model path if provided
set model_path [expr {$custom_model_path ne "" ? $custom_model_path : $default_model}]
puts "Model: $model_path"

# Load the engine package
puts "\n--- Loading Engine ---"
if {[catch {
    package require $package_name
    puts "✓ $package_name package loaded successfully"
} err]} {
    puts "✗ Failed to load $package_name package: $err"
    exit 1
}

# Show available commands
puts "\nAvailable commands:"
foreach cmd [lsort [info commands *${engine}*]] {
    puts "  $cmd"
}

# Test model creation
puts "\n--- Testing Model Creation ---"
if {[catch {
    set model [$create_cmd -path $model_path]
    puts "✓ Model created: $model"
} err]} {
    puts "✗ Model creation failed: $err"
    exit 1
}

# Test recognizer creation
puts "\n--- Testing Recognizer Creation ---"
if {[catch {
    set recognizer [$model create_recognizer -rate 16000]
    puts "✓ Recognizer created: $recognizer"
} err]} {
    puts "✗ Recognizer creation failed: $err"
    exit 1
}

# Test with silence (dummy audio)
puts "\n--- Testing with Silence ---"
if {[catch {
    set silence_data [binary format s* [lrepeat 1600 0]]
    set result [$recognizer accept-waveform $silence_data]
    puts "✓ accept-waveform result: $result"

    set text [$recognizer text]
    puts "✓ partial text: '$text'"

    set final [$recognizer final-result]
    puts "✓ final result: '$final'"
} err]} {
    puts "✗ Audio processing failed: $err"
}

# Test with simple tone (sine wave)
puts "\n--- Testing with Test Audio ---"
if {[catch {
    # Generate a simple 440Hz tone for 0.1 seconds
    set sample_rate 16000
    set duration 0.1
    set frequency 440.0
    set samples [expr {int($sample_rate * $duration)}]

    set audio_data {}
    for {set i 0} {$i < $samples} {incr i} {
        set t [expr {$i / double($sample_rate)}]
        set amplitude [expr {sin(2 * 3.14159 * $frequency * $t)}]
        set sample [expr {int($amplitude * 16383)}]
        append audio_data [binary format s $sample]
    }

    set result [$recognizer accept-waveform $audio_data]
    puts "✓ Test audio processed: $result"

    set text [$recognizer text]
    puts "✓ Partial text: '$text'"
} err]} {
    puts "✗ Test audio processing failed: $err"
}

# Test reset functionality
puts "\n--- Testing Reset ---"
if {[catch {
    $recognizer reset
    puts "✓ Recognizer reset successful"
} err]} {
    puts "✗ Reset failed: $err"
}

# Clean up
puts "\n--- Cleanup ---"
if {[catch {
    $recognizer close
    puts "✓ Recognizer closed"

    $model close
    puts "✓ Model closed"
} err]} {
    puts "✗ Cleanup failed: $err"
}

puts "\n=== Test Complete ==="
puts "✓ $engine engine test completed successfully!"