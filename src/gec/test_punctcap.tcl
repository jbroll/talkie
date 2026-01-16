#!/usr/bin/env tclsh
# Test punctuation and capitalization restoration with DistilBERT

# Setup paths
set script_dir [file dirname [info script]]
lappend auto_path [file normalize $script_dir/lib]
lappend auto_path [file normalize $script_dir/../wordpiece/lib]

# Load packages
package require gec
package require wordpiece
source [file join $script_dir punctcap.tcl]

puts "=== Punctuation & Capitalization Tests ==="
puts ""

# Find model and vocab files
set model_path [file normalize $script_dir/../../models/gec/distilbert-punct-cap.onnx]
set vocab_path [file normalize $script_dir/vocab.txt]

if {![file exists $model_path]} {
    puts "ERROR: Model not found at $model_path"
    exit 1
}
if {![file exists $vocab_path]} {
    puts "ERROR: Vocab not found at $vocab_path"
    exit 1
}

# Initialize
puts "Initializing punctuation/capitalization restoration..."
puts "  Model: $model_path"
puts "  Vocab: $vocab_path"

# Try NPU first, fall back to CPU if unavailable
set device "NPU"
if {[catch {punctcap::init -model $model_path -vocab $vocab_path -device NPU}]} {
    puts "  NPU unavailable, falling back to CPU..."
    set device "CPU"
    punctcap::init -model $model_path -vocab $vocab_path -device CPU
}
puts "  Device: $device"
puts ""

# Test cases - Format: {input expected_patterns}
# expected_patterns: list of substrings that must appear in output
set test_cases {
    {"hello world" {"Hello" "."}}
    {"what is your name" {"What" "?" "name"}}
    {"how are you" {"How" "?"}}
    {"my name is john and i live here" {"My" "John" "I"}}
    {"i went to new york" {"I" "New York"}}
    {"this is amazing" {"This" "."}}
    {"the quick brown fox" {"The" "fox"}}
    {"good morning everyone" {"Good"}}
}

puts "Running test cases..."
puts ""

set passed 0
set failed 0

foreach test $test_cases {
    lassign $test input patterns

    puts "Input:    \"$input\""

    set output [punctcap::restore $input]
    puts "Output:   \"$output\""

    # Check all expected patterns appear
    set all_found 1
    set missing {}
    foreach pattern $patterns {
        if {[string first $pattern $output] == -1} {
            set all_found 0
            lappend missing $pattern
        }
    }

    if {$all_found} {
        puts "Status:   PASS"
        incr passed
    } else {
        puts "Status:   FAIL (missing: $missing)"
        incr failed
    }
    puts ""
}

# Benchmark
puts "=== Performance Benchmark ==="
puts ""

# Warmup
for {set i 0} {$i < 5} {incr i} {
    punctcap::restore "hello world how are you doing today"
}

# Benchmark
set iterations 20
set start [clock microseconds]
for {set i 0} {$i < $iterations} {incr i} {
    punctcap::restore "the quick brown fox jumps over the lazy dog"
}
set elapsed [expr {([clock microseconds] - $start) / double($iterations)}]

puts "NPU Latency: [format %.2f [expr {$elapsed / 1000.0}]] ms"
puts ""

# Summary
puts "=== Results ==="
puts "Passed: $passed"
puts "Failed: $failed"
puts "Total:  [expr {$passed + $failed}]"
puts "Accuracy: [format %.1f [expr {100.0 * $passed / ($passed + $failed)}]]%"

# Cleanup
punctcap::cleanup

if {$failed > 0} {
    exit 1
}
puts ""
puts "All tests passed!"
