# vad_silero.tcl - Silero VAD module using OpenVINO
#
# Model: silero_vad_ifless.onnx (opset 18, no If control flow)
# Tensor layout:
#   input 0: "input"  f32 [1, 512]  - audio window (512 samples = 32ms @ 16kHz)
#   input 1: "sr"     i64 scalar    - sample rate (skip; model is 16kHz-only)
#   input 2: "state"  f32 [2,1,128] - LSTM state (zeros on first call)
#   output 0: "output" f32 [1,1]   - speech probability
#   output 1: "stateN" f32 [2,1,128] - updated LSTM state
#
# Frame accumulation: PortAudio delivers 400 samples/callback (25ms).
# Silero needs 512 samples (32ms). Accumulate int16 bytes until enough.

namespace eval ::vad::silero {
    variable model ""
    variable request ""
    variable state {}           ;# [2,1,128] = 256 floats, zeros init
    variable accumulator ""     ;# binary int16 accumulator
    variable initialized 0
    variable threshold 0.5

    # Window size in samples (must be >= 160 for this model)
    variable window_samples 512
    variable window_bytes   1024 ;# 512 * 2 bytes per int16

    proc init {model_path {device CPU} {threshold_val 0.5}} {
        variable model
        variable request
        variable state
        variable accumulator
        variable initialized
        variable threshold
        variable window_samples

        set threshold $threshold_val

        if {[catch {
            set model [ov::load_model -path $model_path -device $device]
            set request [$model create_request]
        } err]} {
            error "vad::silero::init failed: $err"
        }

        # Initialize LSTM state to zeros [2, 1, 128] = 256 floats
        set state [lrepeat 256 0.0]
        set accumulator ""
        set initialized 1
    }

    # Convert binary int16 PCM bytes to list of normalized f32 values [-1,1]
    proc _to_float {bytes} {
        binary scan $bytes s* samples
        return [lmap s $samples {expr {$s / 32768.0}}]
    }

    # Process a chunk of int16 audio data (binary bytes).
    # Accumulates samples. Returns speech probability (0.0-1.0) when a
    # complete window is ready, or -1.0 if not enough data yet.
    proc process {int16_data} {
        variable request
        variable state
        variable accumulator
        variable initialized
        variable window_bytes
        variable window_samples

        if {!$initialized} { return -1.0 }

        append accumulator $int16_data

        # Not enough data yet
        if {[string length $accumulator] < $window_bytes} {
            return -1.0
        }

        # Extract one window, keep remainder
        set window [string range $accumulator 0 [expr {$window_bytes - 1}]]
        set accumulator [string range $accumulator $window_bytes end]

        # Convert int16 → float list
        set audio_floats [_to_float $window]

        # Run inference
        $request set_input 0 $audio_floats -type f32 -shape [list 1 $window_samples]
        $request set_input 2 $state -type f32 -shape {2 1 128}
        $request infer

        # Read speech probability
        set out [$request get_output 0]
        set prob [lindex [dict get $out data] 0]

        # Carry state forward
        set state_out [$request get_output 1]
        set state [dict get $state_out data]

        return $prob
    }

    # Reset LSTM state and accumulator (call at utterance boundaries)
    proc reset {} {
        variable state
        variable accumulator
        set state [lrepeat 256 0.0]
        set accumulator ""
    }

    proc cleanup {} {
        variable model
        variable request
        variable initialized

        set initialized 0
        if {$request ne ""} { catch {$request close}; set request "" }
        if {$model ne ""} { catch {$model close}; set model "" }
    }
}
