#!/usr/bin/env tclsh
# test_coprocess.tcl - Test the speech engine coprocess protocol

lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"
package require json

# Load coprocess manager
source coprocess.tcl

proc test_protocol {} {
    puts "=== Testing Faster-Whisper Coprocess Protocol ==="

    # Use local model
    set model_path "../models/faster-whisper"
    if {![file exists $model_path]} {
        puts "ERROR: Model not found at $model_path"
        puts "Run this to download: source venv/bin/activate && python3 -c \"from faster_whisper import download_model; download_model('tiny.en', output_dir='./models/faster-whisper')\""
        return
    }

    puts "\n1. Starting engine..."
    puts "   Using model: $model_path"
    set response [::coprocess::start "test-engine" \
        "engines/faster_whisper_wrapper.sh" \
        $model_path \
        16000]

    puts "   Response: $response"
    set response_dict [json::json2dict $response]

    if {[dict get $response_dict status] ne "ok"} {
        puts "ERROR: Engine failed to start"
        return
    }

    puts "   ✓ Engine: [dict get $response_dict engine]"
    puts "   ✓ Version: [dict get $response_dict version]"

    puts "\n2. Testing PROCESS with empty audio..."
    # Create 100ms of silence (1600 samples @ 16kHz, int16)
    set silence [binary format s* [lrepeat 1600 0]]

    set response [::coprocess::process "test-engine" $silence]
    puts "   Response: $response"
    set response_dict [json::json2dict $response]

    if {[dict exists $response_dict partial]} {
        puts "   ✓ Got partial result: '[dict get $response_dict partial]'"
    }

    puts "\n3. Testing FINAL..."
    set response [::coprocess::final "test-engine"]
    puts "   Response: $response"
    set response_dict [json::json2dict $response]

    if {[dict exists $response_dict alternatives]} {
        set text [dict get $response_dict alternatives 0 text]
        set conf [dict get $response_dict alternatives 0 confidence]
        puts "   ✓ Text: '$text'"
        puts "   ✓ Confidence: $conf"
    }

    puts "\n4. Testing RESET..."
    set response [::coprocess::reset "test-engine"]
    puts "   Response: $response"
    set response_dict [json::json2dict $response]

    if {[dict get $response_dict status] eq "ok"} {
        puts "   ✓ Reset successful"
    }

    puts "\n5. Stopping engine..."
    ::coprocess::stop "test-engine"
    puts "   ✓ Engine stopped"

    puts "\n=== Test Complete ==="
}

# Run test
test_protocol
