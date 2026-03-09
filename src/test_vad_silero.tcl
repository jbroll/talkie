#!/usr/bin/env tclsh
# test_vad_silero.tcl - Tests for Silero VAD module

set script_dir [file dirname [file normalize [info script]]]

# Load ov package
lappend ::auto_path [file join $script_dir ov lib ov]
package require ov

# Source the VAD module
source [file join $script_dir vad_silero.tcl]

set model_path [file join $script_dir .. models vad silero_vad_ifless.onnx]
set pass 0; set fail 0

proc assert_approx {label got expected tol} {
    global pass fail
    set err [expr {abs($got - $expected)}]
    if {$err <= $tol} {
        puts "  PASS $label: $got (expected ~$expected)"
        incr pass
    } else {
        puts "  FAIL $label: $got (expected ~$expected, tol=$tol)"
        incr fail
    }
}

proc assert_range {label got lo hi} {
    global pass fail
    if {$got >= $lo && $got <= $hi} {
        puts "  PASS $label: $got (range \[$lo,$hi\])"
        incr pass
    } else {
        puts "  FAIL $label: $got (expected in \[$lo,$hi\])"
        incr fail
    }
}

proc assert_eq {label got expected} {
    global pass fail
    if {$got eq $expected} {
        puts "  PASS $label: $got"
        incr pass
    } else {
        puts "  FAIL $label: got='$got' expected='$expected'"
        incr fail
    }
}

# ---- Test 1: Model loads ----------------------------------------
puts "\nTest 1: Init"
if {[catch {::vad::silero::init $model_path CPU 0.5} err]} {
    puts "  FAIL init: $err"
    incr fail
    puts "\nFATAL: cannot continue without model"
    exit 1
} else {
    puts "  PASS init: model loaded"
    incr pass
}

# ---- Test 2: Silence returns low probability -------------------
puts "\nTest 2: Silence → low probability"
set silence [binary format s512 [lrepeat 512 0]]
set prob [::vad::silero::process $silence]
assert_range "silence prob" $prob -0.01 0.1

# ---- Test 3: State carry-forward --------------------------------
puts "\nTest 3: State carry-forward"
set state_before $::vad::silero::state
set prob2 [::vad::silero::process $silence]
set state_after $::vad::silero::state
# States should differ after two forward passes
set same [expr {$state_before eq $state_after}]
assert_eq "state updated" $same 0

# ---- Test 4: Reset zeros the state ------------------------------
puts "\nTest 4: Reset"
::vad::silero::reset
set all_zero 1
foreach v $::vad::silero::state {
    if {$v != 0.0} { set all_zero 0; break }
}
assert_eq "state zeroed after reset" $all_zero 1
assert_eq "accumulator cleared" [string length $::vad::silero::accumulator] 0

# ---- Test 5: Accumulation with 400-sample chunks ---------------
puts "\nTest 5: Accumulation (400-sample chunks)"
::vad::silero::reset
# PortAudio delivers 400 samples (800 bytes) per callback
set chunk_400 [binary format s400 [lrepeat 400 0]]
# First chunk: 800 bytes < 1024 (window_bytes) → returns -1
set r1 [::vad::silero::process $chunk_400]
assert_eq "chunk1 not enough" $r1 -1.0

# After first chunk, accumulator has 800 bytes
assert_eq "accumulator after chunk1" [string length $::vad::silero::accumulator] 800

# Second chunk: 800+800=1600 bytes → fires inference (1024 consumed, 576 remain)
set r2 [::vad::silero::process $chunk_400]
assert_range "chunk2 fires inference" $r2 0.0 1.0
assert_eq "remainder after chunk2" [string length $::vad::silero::accumulator] 576

# Third chunk: 576+800=1376 bytes → fires inference (1024 consumed, 352 remain)
set r3 [::vad::silero::process $chunk_400]
assert_range "chunk3 fires inference" $r3 0.0 1.0
assert_eq "remainder after chunk3" [string length $::vad::silero::accumulator] 352

# ---- Test 6: Threshold test with pure silence ------------------
puts "\nTest 6: Threshold"
::vad::silero::reset
set prob [::vad::silero::process $silence]
set below_threshold [expr {$prob < 0.5}]
assert_eq "silence below threshold" $below_threshold 1

# ---- Test 7: Latency benchmark ----------------------------------
puts "\nTest 7: Latency benchmark"
::vad::silero::reset
set window [binary format s512 [lrepeat 512 0]]
# Warm up
::vad::silero::process $window

set n 200
set t0 [clock microseconds]
for {set i 0} {$i < $n} {incr i} {
    ::vad::silero::process $window
}
set elapsed_us [expr {([clock microseconds] - $t0) / double($n)}]
puts "  avg latency: [format %.1f $elapsed_us]us per inference"
if {$elapsed_us < 5000} {
    puts "  PASS latency < 5ms"
    incr pass
} else {
    puts "  FAIL latency: [format %.1f $elapsed_us]us (target < 5000us)"
    incr fail
}

# ---- Cleanup ---------------------------------------------------
::vad::silero::cleanup

puts "\n=== Results: $pass passed, $fail failed ==="
if {$fail > 0} { exit 1 }
