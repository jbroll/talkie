#!/usr/bin/env tclsh
# Test suite for ov (OpenVINO) critcl bindings

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

puts "=== ov OpenVINO Bindings Tests ==="
set passed 0
set failed 0

# Load package
puts "\nLoading package..."
if {[catch {package require ov} err]} {
    puts "FAIL: Could not load ov package: $err"
    puts "Make sure LD_LIBRARY_PATH includes OpenVINO and NPU driver libraries"
    exit 1
}
puts "Loaded ov [package present ov]"

puts "\nRunning tests...\n"

# Test: version
if {[test "ov::version returns OpenVINO info" {
    set ver [ov::version]
    assert {[dict exists $ver build]} "Should have build key"
    assert {[dict exists $ver description]} "Should have description key"
    assert {[string match "*OpenVINO*" [dict get $ver description]]} "Should be OpenVINO"
}]} {incr passed} else {incr failed}

# Test: devices
if {[test "ov::devices lists available devices" {
    set devs [ov::devices]
    assert {[llength $devs] > 0} "Should have at least one device"
    assert {"CPU" in $devs} "Should have CPU device"
}]} {incr passed} else {incr failed}

# Test: NPU device (if available)
if {[test "NPU device available" {
    set devs [ov::devices]
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
    if {[test "load_model on CPU returns ov_model* handle" {
        set model [ov::load_model -path $model_file -device CPU]
        assert {[string match "ov_model*" $model]} "Should return ov_model* handle"
        $model close
    }]} {incr passed} else {incr failed}

    # Test: model info
    if {[test "model info returns metadata dict" {
        set model [ov::load_model -path $model_file -device CPU]
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
    if {[test "create_request returns ov_infer* handle" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]
        assert {[string match "ov_infer*" $req]} "Should return ov_infer* handle"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: backward compat - set_input with no flags (I64, [1,N])
    if {[test "set_input backward compat: no flags uses i64 shape {1 N}" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]
        set data [lrepeat 64 101]
        set result [$req set_input 0 $data]
        assert {$result eq "ok"} "Should return ok"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: explicit -type i64 (same as default)
    if {[test "set_input -type i64 explicit same as default" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]
        set data [lrepeat 64 101]
        set result [$req set_input 0 $data -type i64]
        assert {$result eq "ok"} "Should return ok"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: typed input - f32 creates tensor (model type mismatch is OpenVINO-level validation)
    if {[test "set_input -type f32 creates tensor, reaches OpenVINO validation" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]
        set data [lrepeat 64 1.0]
        # ELECTRA uses I64; OpenVINO will reject F32 with ParameterMismatch (not a crash)
        set caught [catch {$req set_input 0 $data -type f32} err]
        assert {$caught} "Should raise OpenVINO type mismatch error"
        assert {[string match "*precision*" $err] || [string match "*ParameterMismatch*" $err] || [string match "*GENERAL_ERROR*" $err]} \
            "Error should be from OpenVINO type validation"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: typed input - i32 creates tensor (model type mismatch is OpenVINO-level validation)
    if {[test "set_input -type i32 creates tensor, reaches OpenVINO validation" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]
        set data [lrepeat 64 101]
        # ELECTRA uses I64; OpenVINO will reject I32 with ParameterMismatch (not a crash)
        set caught [catch {$req set_input 0 $data -type i32} err]
        assert {$caught} "Should raise OpenVINO type mismatch error"
        assert {[string match "*precision*" $err] || [string match "*ParameterMismatch*" $err] || [string match "*GENERAL_ERROR*" $err]} \
            "Error should be from OpenVINO type validation"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: custom shape
    if {[test "set_input -shape {1 64} works" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]
        set data [lrepeat 64 101]
        set result [$req set_input 0 $data -shape {1 64}]
        assert {$result eq "ok"} "Should return ok"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: shape validation - mismatch error
    if {[test "set_input shape mismatch raises error" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]
        set data [lrepeat 64 101]
        set caught [catch {$req set_input 0 $data -shape {1 32}} err]
        assert {$caught} "Should raise an error"
        assert {[string match "*64*" $err] || [string match "*32*" $err]} \
            "Error should mention sizes"
        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: full inference cycle
    if {[test "full inference cycle: set_input, infer, get_output" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]

        set input_ids [lrepeat 64 101]
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

    # Test: get_best_token
    if {[test "get_best_token returns {id logit} pair" {
        set model [ov::load_model -path $model_file -device CPU]
        set req [$model create_request]

        set input_ids [lrepeat 64 101]
        set attention_mask [lrepeat 64 1]

        $req set_input 0 $input_ids
        $req set_input 1 $attention_mask
        $req infer

        set result [$req get_best_token 0 1 {101 102 103 2000 2001}]
        assert {[llength $result] == 2} "Should return list of 2"
        set best_id [lindex $result 0]
        set best_logit [lindex $result 1]
        assert {$best_id >= 0} "Best ID should be non-negative"
        assert {[string is double -strict $best_logit]} "Logit should be a number"

        $req close
        $model close
    }]} {incr passed} else {incr failed}

    # Test: NPU inference (if available)
    set devs [ov::devices]
    if {"NPU" in $devs} {
        if {[test "inference on NPU" {
            set model [ov::load_model -path $model_file -device NPU]
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

        # Test: NPU vs CPU benchmark
        if {[test "NPU is faster than CPU" {
            # CPU benchmark
            set model_cpu [ov::load_model -path $model_file -device CPU]
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
            set model_npu [ov::load_model -path $model_file -device NPU]
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
