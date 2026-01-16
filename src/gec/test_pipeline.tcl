#!/usr/bin/env tclsh
# Test GEC pipeline integration

# Setup paths
set script_dir [file dirname [info script]]
lappend auto_path [file normalize $script_dir/lib]
lappend auto_path [file normalize $script_dir/../wordpiece/lib]

# Load pipeline
source [file join $script_dir pipeline.tcl]

puts "=== GEC Pipeline Integration Tests ==="
puts ""

# Find model and data files
set punctcap_model [file normalize $script_dir/../../models/gec/distilbert-punct-cap.onnx]
set homophone_model [file normalize $script_dir/../../models/gec/electra-small-generator.onnx]
set vocab_path [file normalize $script_dir/vocab.txt]
set homophones_path [file normalize $script_dir/../../data/homophones.json]

foreach {name path} [list \
    "Punctcap model" $punctcap_model \
    "Homophone model" $homophone_model \
    "Vocab" $vocab_path \
    "Homophones" $homophones_path] {
    if {![file exists $path]} {
        puts "ERROR: $name not found at $path"
        exit 1
    }
}

# Initialize pipeline with fallback to CPU
puts "Initializing GEC pipeline..."
set device "NPU"
if {[catch {
    gec_pipeline::init \
        -punctcap_model $punctcap_model \
        -homophone_model $homophone_model \
        -vocab $vocab_path \
        -homophones $homophones_path \
        -device NPU
} err]} {
    puts "  NPU unavailable, falling back to CPU..."
    set device "CPU"
    gec_pipeline::init \
        -punctcap_model $punctcap_model \
        -homophone_model $homophone_model \
        -vocab $vocab_path \
        -homophones $homophones_path \
        -device CPU
}
puts "  Device: $device"
puts ""

# Test cases simulating Vosk output
# Format: {vosk_output expected_patterns}
# Tests focus on: sentence-start capitalization, homophone correction, punctuation
set test_cases {
    {"hello how are you" {"Hello" "?"}}
    {"i went to there house" {"I" "their"}}
    {"turn write at the light" {"right"}}
    {"you're car is very nice" {"your" "car"}}
    {"it's engine is powerful" {"its" "engine"}}
    {"i sea the boat" {"I" "see" "boat"}}
    {"what is you're name" {"What" "?" "your"}}
    {"take a peak at this" {"peek"}}
    {"the plain landed safely" {"plane"}}
    {"i wonder weather it will rain" {"whether"}}
}

puts "=== Pipeline Tests ==="
puts ""

set passed 0
set failed 0

foreach test $test_cases {
    lassign $test input patterns

    puts "Input:    \"$input\""

    set output [gec_pipeline::process $input]
    puts "Output:   \"$output\""

    # Check all expected patterns appear (case-insensitive for words)
    set all_found 1
    set missing {}
    set output_lower [string tolower $output]
    foreach pattern $patterns {
        set pattern_lower [string tolower $pattern]
        if {[string first $pattern_lower $output_lower] == -1} {
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

# Performance benchmark
puts "=== Performance Benchmark ==="
puts ""

# Warmup
for {set i 0} {$i < 5} {incr i} {
    gec_pipeline::process "hello how are you today"
}

# Benchmark
set iterations 20
set start [clock microseconds]
for {set i 0} {$i < $iterations} {incr i} {
    gec_pipeline::process "the quick brown fox jumps over the lazy dog"
}
set elapsed [expr {([clock microseconds] - $start) / double($iterations)}]

puts "Pipeline Latency: [format %.2f [expr {$elapsed / 1000.0}]] ms"
puts ""

# Show stats
puts "=== Pipeline Statistics ==="
set stats [gec_pipeline::stats]
puts "Processed: [dict get $stats processed]"
puts "Punct changes: [dict get $stats punct_changes]"
puts "Homo changes: [dict get $stats homo_changes]"
puts "Avg latency: [format %.2f [dict get $stats avg_ms]] ms"
puts ""

# Summary
puts "=== Results ==="
puts "Passed: $passed"
puts "Failed: $failed"
puts "Total:  [expr {$passed + $failed}]"
puts "Accuracy: [format %.1f [expr {100.0 * $passed / ($passed + $failed)}]]%"

# Cleanup
gec_pipeline::cleanup

if {$failed > 0} {
    exit 1
}
puts ""
puts "All tests passed!"
