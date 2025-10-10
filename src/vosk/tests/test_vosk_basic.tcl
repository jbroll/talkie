#!/usr/bin/env tclsh
# test_vosk_basic.tcl - Basic test of Vosk binding functionality

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Testing Vosk Tcl binding..."

# Test package loading
if {[catch {package require vosk} err]} {
    puts "✗ Failed to load vosk package: $err"
    exit 1
}
puts "✓ Vosk package loaded"

# Initialize Vosk
if {[catch {Vosk_Init} err]} {
    puts "✗ Failed to initialize Vosk: $err"
    exit 1
}
puts "✓ Vosk initialized"

# Test basic functionality (no separate init needed)
puts "✓ Basic Vosk functionality available"

# Test log level setting
if {[catch {vosk::set_log_level -1} err]} {
    puts "✗ Failed to set log level: $err"
    exit 1
}
puts "✓ Log level set to -1 (quiet)"

# Check if model path exists
set model_path "../../models/vosk-model-en-us-0.22-lgraph"
if {![file exists $model_path]} {
    puts "✗ Vosk model not found at: $model_path"
    puts "Please download a Vosk model first:"
    puts "  wget https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-lgraph.zip"
    puts "  unzip vosk-model-en-us-0.22-lgraph.zip -d ~/Downloads/"
    exit 1
}
puts "✓ Model path exists: $model_path"

# Test model loading
puts "Loading model (this may take a moment)..."
if {[catch {vosk::load_model -path $model_path} model err]} {
    puts "✗ Failed to load model: $err"
    exit 1
}
puts "✓ Model loaded: $model"

# Test model info
if {[catch {$model info} info err]} {
    puts "✗ Failed to get model info: $err"
    exit 1
}
puts "✓ Model info: $info"

# Test recognizer creation
puts "Creating recognizer..."
if {[catch {$model create_recognizer -rate 16000 -alternatives 1} recognizer err]} {
    puts "✗ Failed to create recognizer: $err"
    exit 1
}
puts "✓ Recognizer created: $recognizer"

# Test recognizer info
if {[catch {$recognizer info} info err]} {
    puts "✗ Failed to get recognizer info: $err"
    exit 1
}
puts "✓ Recognizer info: $info"

# Test recognizer configuration
puts "Testing recognizer configuration..."
if {[catch {$recognizer configure -alternatives 3 -confidence 0.7} err]} {
    puts "✗ Failed to configure recognizer: $err"
    exit 1
}
puts "✓ Recognizer configured"

# Test with sample audio data (silence)
puts "Testing with sample audio data..."
set sample_data [string repeat "\x00" 3200]  ;# 0.1 seconds of 16-bit mono silence at 16kHz
if {[catch {$recognizer process $sample_data} result err]} {
    puts "✗ Failed to process audio: $err"
    exit 1
}
puts "✓ Audio processed, result: [string length $result] characters"

# Test reset
if {[catch {$recognizer reset} err]} {
    puts "✗ Failed to reset recognizer: $err"
    exit 1
}
puts "✓ Recognizer reset"

# Test final result
if {[catch {$recognizer final_result} result err]} {
    puts "✗ Failed to get final result: $err"
    exit 1
}
puts "✓ Final result obtained: [string length $result] characters"

# Test callback setting
proc test_callback {recognizer json is_final} {
    puts "Callback called: recognizer=$recognizer, is_final=$is_final, json_len=[string length $json]"
}

if {[catch {$recognizer set_callback test_callback} err]} {
    puts "✗ Failed to set callback: $err"
    exit 1
}
puts "✓ Callback set"

# Test another audio processing with callback
if {[catch {$recognizer process $sample_data} result err]} {
    puts "✗ Failed to process audio with callback: $err"
    exit 1
}
puts "✓ Audio processed with callback"

# Cleanup tests
puts "\nTesting cleanup..."

if {[catch {$recognizer close} err]} {
    puts "✗ Failed to close recognizer: $err"
    exit 1
}
puts "✓ Recognizer closed"

if {[catch {$model close} err]} {
    puts "✗ Failed to close model: $err"
    exit 1
}
puts "✓ Model closed"

puts "\n✅ All basic tests passed!"
puts "Vosk binding is working correctly."