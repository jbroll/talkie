#!/usr/bin/env tclsh
# test_no_callbacks_multiple.tcl - Test multiple calls without callbacks

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Testing multiple calls without callbacks..."

# Load vosk package
package require vosk
Vosk_Init

# Load model
set model_path "../../models/vosk-model-en-us-0.22-lgraph"
set model [vosk::load_model -path $model_path]
puts "✓ Model loaded: $model"

# Create recognizer WITHOUT callback
set recognizer [$model create_recognizer -rate 16000]
puts "✓ Recognizer created: $recognizer"

# Process test audio data multiple times
set test_data [string repeat "\x00\x01\x00\x01" 800]  ;# 3200 bytes of test data

puts "Processing test audio data 10 times WITHOUT callbacks..."
for {set i 1} {$i <= 10} {incr i} {
    puts "Processing chunk $i..."
    set result [$recognizer process $test_data]
    puts "Result: $result"
    after 100  ;# Small delay
}

puts "Getting final result..."
set final [$recognizer final_result]
puts "Final result: $final"

puts "Cleanup..."
$recognizer close
$model close

puts "✅ Multiple calls test completed successfully!"