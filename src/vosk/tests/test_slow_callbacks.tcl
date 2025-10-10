#!/usr/bin/env tclsh
# test_slow_callbacks.tcl - Test callback with delays to avoid rapid calls

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Testing synchronous functionality with delays..."

# Load vosk package
package require vosk
Vosk_Init

# Load model
set model_path "../../models/vosk-model-en-us-0.22-lgraph"
set model [vosk::load_model -path $model_path]
puts "✓ Model loaded: $model"

# Create recognizer without callback (callback feature removed)
set recognizer [$model create_recognizer -rate 16000]
puts "✓ Recognizer created: $recognizer"

# Process test audio data with delays
set test_data [string repeat "\x00\x01\x00\x01" 800]  ;# 3200 bytes of test data

puts "Processing test audio data slowly (5 chunks with 1s delays)..."

for {set i 1} {$i <= 5} {incr i} {
    puts "Processing chunk $i..."

    set result [$recognizer process $test_data]
    puts "Direct result: $result"

    puts "Waiting 1 second before next chunk..."
    after 1000
}

puts "Getting final result..."
set final [$recognizer final_result]
puts "Final result: $final"

puts "Cleanup..."
$recognizer close
$model close

puts "✅ Synchronous test with delays completed successfully!"