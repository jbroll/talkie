#!/usr/bin/env tclsh
# Test suite for GEC (Grammar Error Correction) OpenVINO bindings

# Setup - requires LD_LIBRARY_PATH to be set for OpenVINO
lappend auto_path [file normalize [file dirname [info script]]/lib]

proc assert {condition msg} {
    if {![uplevel 1 [list expr $condition]]} {
        error "FAIL: $msg"
    }
}

proc test {name body} {
    puts -nonewline "  $name... "
    if {[catch {uplevel 1 $body} err]} {
        puts "FAIL"
        puts "    Error: $err"
        return 0
    }
    puts "OK"
    return 1
}

puts "=== GEC OpenVINO Bindings Tests ==="
set passed 0
set failed 0

# Load package
puts "\nLoading package..."
if {[catch {package require gec} err]} {
    puts "FAIL: Could not load gec package: $err"
    puts "Make sure LD_LIBRARY_PATH includes OpenVINO and NPU driver libraries"
    exit 1
}
puts "Loaded gec [package present gec]"

puts "\nRunning tests...\n"

# Test: version
if {[test "gec::version returns OpenVINO info" {
    set ver [gec::version]
    assert {[dict exists $ver build]} "Should have build key"
    assert {[dict exists $ver description]} "Should have description key"
    assert {[string match "*OpenVINO*" [dict get $ver description]]} "Should be OpenVINO"
}]} {incr passed} else {incr failed}

# Test: devices
if {[test "gec::devices lists available devices" {
    set devs [gec::devices]
    assert {[llength $devs] > 0} "Should have at least one device"
    assert {"CPU" in $devs} "Should have CPU device"
}]} {incr passed} else {incr failed}

# Test: NPU device (if available)
if {[test "NPU device available" {
    set devs [gec::devices]
    assert {"NPU" in $devs} "NPU device should be available"
}]} {incr passed} else {incr failed}

# Find model file
set model_dir [file normalize [file dirname [info script]]/../../models/gec]
set model_file "$model_dir/electra-small-generator.onnx"

if {![file exists $model_file]} {
    puts "\nSkipping model tests - model file not found at $model_file"
} else {
    puts "\nModel tests (using $model_file)...\n"

    # Test: load model on CPU
    if {[test "load_model on CPU" {
        set model [gec::load_model -path $model_file -device CPU]
        assert {[string match "gec_model*" $model]} "Should return model handle"
        $model close
    }]} {incr passed} else {incr failed}

    # Test: model info
    if {[test "model info returns metadata" {
        set model [gec::load_model -path $model_file -device CPU]
        set info [$model info]
        assert {[dict exists $info path]} "Should have path"
        assert {[dict exists $info device]} "Should have device"
        assert {[dict exists $info inputs]} "Should have inputs count"
        assert {[dict exists $info outputs]} "Should have outputs count"
        assert {[dict get $info inputs] == 2} "ELECTRA should have 2 inputs"
        assert {[dict get $info outputs] == 1} "ELECTRA should have 1 output"
        $model close
    }]} {incr passed} else {incr failed}

    # Test: create infer request
    if {[test "create_request returns handle" {
        set model [gec::load_model -path $model_file -device CPU]
        set req [$model create_request]
        assert {[string match "gec_infer*" $req]} "Should return request handle"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: inference on CPU
    if {[test "inference produces output" {
        set model [gec::load_model -path $model_file -device CPU]
        set req [$model create_request]

        # Set inputs (64 tokens)
        set input_ids [lrepeat 64 101]  ;# [CLS] tokens
        set attention_mask [lrepeat 64 1]

        $req set_input 0 $input_ids
        $req set_input 1 $attention_mask
        $req infer

        set output [$req get_output 0]
        assert {[dict exists $output shape]} "Output should have shape"
        assert {[dict exists $output data]} "Output should have data"

        set shape [dict get $output shape]
        assert {[lindex $shape 0] == 1} "Batch size should be 1"
        assert {[lindex $shape 1] == 64} "Sequence length should be 64"
        assert {[lindex $shape 2] == 30522} "Vocab size should be 30522"

        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: NPU inference (if available)
    set devs [gec::devices]
    if {"NPU" in $devs} {
        if {[test "inference on NPU" {
            set model [gec::load_model -path $model_file -device NPU]
            set req [$model create_request]

            set input_ids [lrepeat 64 101]
            set attention_mask [lrepeat 64 1]

            $req set_input 0 $input_ids
            $req set_input 1 $attention_mask
            $req infer

            set output [$req get_output 0]
            set shape [dict get $output shape]
            assert {[lindex $shape 2] == 30522} "NPU output should match CPU"

            $req close
            $model close
        }]} {incr passed} else {incr failed}

        # Test: NPU benchmark
        if {[test "NPU is faster than CPU" {
            # CPU benchmark
            set model_cpu [gec::load_model -path $model_file -device CPU]
            set req_cpu [$model_cpu create_request]
            set input_ids [lrepeat 64 101]
            set attention_mask [lrepeat 64 1]
            $req_cpu set_input 0 $input_ids
            $req_cpu set_input 1 $attention_mask

            # Warmup
            for {set i 0} {$i < 5} {incr i} { $req_cpu infer }

            set start [clock microseconds]
            for {set i 0} {$i < 20} {incr i} { $req_cpu infer }
            set cpu_time [expr {([clock microseconds] - $start) / 20.0}]

            $req_cpu close
            $model_cpu close

            # NPU benchmark
            set model_npu [gec::load_model -path $model_file -device NPU]
            set req_npu [$model_npu create_request]
            $req_npu set_input 0 $input_ids
            $req_npu set_input 1 $attention_mask

            # Warmup
            for {set i 0} {$i < 5} {incr i} { $req_npu infer }

            set start [clock microseconds]
            for {set i 0} {$i < 20} {incr i} { $req_npu infer }
            set npu_time [expr {([clock microseconds] - $start) / 20.0}]

            $req_npu close
            $model_npu close

            puts -nonewline " (CPU: [format %.1f $cpu_time]us, NPU: [format %.1f $npu_time]us) "
            assert {$npu_time < $cpu_time} "NPU should be faster than CPU"
        }]} {incr passed} else {incr failed}
    }
}

# Summary
puts "\n=== Results ==="
puts "Passed: $passed"
puts "Failed: $failed"
puts "Total:  [expr {$passed + $failed}]"

if {$failed > 0} {
    exit 1
}
puts "\nAll tests passed!"
