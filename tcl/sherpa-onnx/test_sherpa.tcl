#!/usr/bin/env tclsh
# test_sherpa.tcl - Test Sherpa-ONNX integration
# Usage: tclsh test_sherpa.tcl [model_path]

set auto_path [linsert $auto_path 0 [file join [file dirname [info script]] lib]]

package require sherpa

# Model path - use argument or default
set model_path [lindex $argv 0]
if {$model_path eq ""} {
    set model_path "models/sherpa-onnx-streaming-zipformer-en-2023-06-26"
}

puts "Sherpa-ONNX Speech Recognition Test"
puts "===================================="
puts "Model path: $model_path\n"

# Load model
puts "Loading model..."
if {[catch {sherpa::load_model -path $model_path} model err]} {
    puts "Error loading model: $err"
    exit 1
}
puts "Model loaded: $model"

# Get model info
puts "\nModel info:"
puts [dict get [$model info] path]

# Create recognizer stream
puts "\nCreating recognizer stream..."
set stream [$model create_recognizer -rate 16000 -max_active_paths 4]
puts "Stream created: $stream"

# Get stream info
puts "\nStream info:"
set info [$stream info]
foreach {key value} $info {
    puts "  $key: $value"
}

# Test with synthetic audio data (silence)
puts "\nTesting with synthetic audio (silence)..."
set samples [binary format s* [lrepeat 1024 0]]
set result [$stream process $samples]
puts "Result: $result"

# Configure stream
puts "\nConfiguring stream..."
$stream configure -confidence 0.5
puts "Configuration updated"

# Get updated info
puts "\nUpdated stream info:"
set info [$stream info]
foreach {key value} $info {
    puts "  $key: $value"
}

# Reset stream
puts "\nResetting stream..."
$stream reset
puts "Stream reset complete"

# Final result
puts "\nGetting final result..."
set final [$stream final-result]
puts "Final result: $final"

# Cleanup
puts "\nCleaning up..."
$stream close
$model close

puts "\n✓ All tests passed!"
puts "\nAPI Compatibility with Vosk:"
puts "  - sherpa::load_model (like vosk::load_model)"
puts "  - \$model create_recognizer (same)"
puts "  - \$stream process (same)"
puts "  - \$stream final-result (same)"
puts "  - \$stream reset (same)"
puts "  - \$stream configure (same)"
puts "  - \$stream info (same)"
puts "  - \$stream close (same)"
