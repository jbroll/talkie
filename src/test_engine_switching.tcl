#!/usr/bin/env tclsh
# Test switching between critcl and coprocess engines

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"
lappend auto_path [file join $script_dir vosk lib vosk]
lappend auto_path [file join $script_dir sherpa-onnx lib sherpa-onnx]

package require json

# Mock the config array
array set ::config {
    speech_engine vosk
    vosk_modelfile vosk-model-en-us-0.22-lgraph
    sherpa_modelfile sherpa-onnx-streaming-zipformer-en-2023-06-26
    faster_whisper_modelfile ""
}

set ::device_sample_rate 16000

# Mock get_model_path for legacy engines
proc get_model_path {modelfile} {
    set model_dir [::engine::get_property $::config(speech_engine) model_dir]
    if {$model_dir eq ""} {
        return ""
    }
    return [file join [file dirname $::script_dir] models $model_dir $modelfile]
}

# Mock print for debug output
proc print {args} {
    puts "  [join $args]"
}

# Load required modules
source [file join $script_dir coprocess.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir engine.tcl]

package require vosk

puts "\n=== Testing Engine Switching ==="

# Test 1: Vosk (critcl engine)
puts "\n--- Test 1: Vosk (critcl) Engine ---"
set ::config(speech_engine) "vosk"
if {[::engine::initialize]} {
    puts "✓ Vosk engine initialized successfully"
    set rec [::engine::recognizer]
    puts "  Recognizer command: $rec"
    puts "  Engine type: [::engine::get_property vosk type]"
    ::engine::cleanup
    puts "✓ Vosk engine cleaned up"
} else {
    puts "✗ Vosk engine initialization FAILED"
}

# Test 2: Faster-Whisper (coprocess engine)
puts "\n--- Test 2: Faster-Whisper (coprocess) Engine ---"
set ::config(speech_engine) "faster-whisper"

# Check if model exists
set model_dir [file join [file dirname $script_dir] models faster-whisper]
if {![file exists $model_dir]} {
    puts "⚠ Faster-whisper model directory not found: $model_dir"
    puts "  Skipping faster-whisper test"
} else {
    if {[::engine::initialize]} {
        puts "✓ Faster-whisper engine initialized successfully"
        set rec [::engine::recognizer]
        puts "  Recognizer command: $rec"
        puts "  Engine type: [::engine::get_property faster-whisper type]"

        # Test a simple command
        puts "\n  Testing RESET command..."
        set response [$rec reset]
        puts "  Response: $response"

        ::engine::cleanup
        puts "✓ Faster-whisper engine cleaned up"
    } else {
        puts "✗ Faster-whisper engine initialization FAILED"
    }
}

# Test 3: Switch back to Vosk
puts "\n--- Test 3: Switch Back to Vosk ---"
set ::config(speech_engine) "vosk"
if {[::engine::initialize]} {
    puts "✓ Successfully switched back to Vosk"
    ::engine::cleanup
} else {
    puts "✗ Failed to switch back to Vosk"
}

puts "\n=== All Tests Complete ==="
