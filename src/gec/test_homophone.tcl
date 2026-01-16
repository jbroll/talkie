#!/usr/bin/env tclsh
# Test homophone correction with ELECTRA MLM

# Setup paths
set script_dir [file dirname [info script]]
lappend auto_path [file normalize $script_dir/lib]
lappend auto_path [file normalize $script_dir/../wordpiece/lib]

# Load packages
package require gec
package require wordpiece
source [file join $script_dir homophone.tcl]

puts "=== Homophone Correction Tests ==="
puts ""

# Find model and vocab files
set model_path [file normalize $script_dir/../../models/gec/electra-small-generator.onnx]
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
puts "Initializing homophone correction..."
puts "  Model: $model_path"
puts "  Vocab: $vocab_path"

# Try NPU first, fall back to CPU if unavailable
set device "NPU"
if {[catch {homophone::init -model $model_path -vocab $vocab_path -device NPU} num_groups]} {
    puts "  NPU unavailable, falling back to CPU..."
    set device "CPU"
    set num_groups [homophone::init -model $model_path -vocab $vocab_path -device CPU]
}
puts "  Device: $device"
puts ""
puts "Loaded $num_groups homophone groups"
puts ""

# Test cases - single-token homophones
# Format: {input_text target_word expected_correction}
# Note: Only homophones present in pronunciation dictionary will work
set test_cases {
    {"I went to there house" "there" "their"}
    {"Turn write at the light" "write" "right"}
    {"The hole thing is wrong" "hole" "whole"}
    {"I want to by a car" "by" "buy"}
    {"I sea the boat" "sea" "see"}
    {"The plain landed safely" "plain" "plane"}
    {"I will steal the show" "steal" "steal"}
    {"Take a peak at this" "peak" "peek"}
    {"It was a dark night" "night" "night"}
    {"The son rose early" "son" "sun"}
}

# Multi-token test cases (contractions misused as possessives/other)
# Format: {input_text contraction expected_replacement}
set multitoken_cases {
    {"i went to they're house" "they're" "their"}
    {"you're car is nice" "you're" "your"}
    {"it's engine is very powerful" "it's" "its"}
}

puts "=== Single-Token Homophones ==="
puts ""

set passed 0
set failed 0

foreach test $test_cases {
    lassign $test input target expected

    puts "Input:    \"$input\""
    puts "Target:   \"$target\" -> \"$expected\""

    # Get correction
    set corrected [homophone::correct $input]
    puts "Output:   \"$corrected\""

    # Check if the target word was corrected properly
    # Use word boundary matching to avoid false matches (e.g., "no" in "know")
    set words [split $corrected " "]
    set has_expected [expr {$expected in $words}]
    set has_target [expr {$target in $words}]

    if {$has_expected && !$has_target} {
        puts "Status:   PASS"
        incr passed
    } elseif {$target eq $expected && $has_target} {
        # Target was already correct, no change needed
        puts "Status:   PASS (no change needed)"
        incr passed
    } else {
        puts "Status:   FAIL"
        incr failed
    }
    puts ""
}

puts "=== Multi-Token Homophones (Contractions) ==="
puts ""

foreach test $multitoken_cases {
    lassign $test input contraction expected

    puts "Input:    \"$input\""
    puts "Target:   \"$contraction\" -> \"$expected\""

    set corrected [homophone::correct $input]
    puts "Output:   \"$corrected\""

    # Check: expected word present, contraction not present
    set has_expected [string match "*$expected*" $corrected]
    set has_contraction [string match "*$contraction*" $corrected]

    if {$has_expected && !$has_contraction} {
        puts "Status:   PASS"
        incr passed
    } else {
        puts "Status:   FAIL"
        incr failed
    }
    puts ""
}

# Summary
puts "=== Results ==="
puts "Passed: $passed"
puts "Failed: $failed"
puts "Total:  [expr {$passed + $failed}]"
puts "Accuracy: [format %.1f [expr {100.0 * $passed / ($passed + $failed)}]]%"

# Cleanup
homophone::cleanup

if {$failed > 0} {
    exit 1
}
puts ""
puts "All tests passed!"
