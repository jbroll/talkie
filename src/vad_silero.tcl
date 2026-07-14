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
# Silero needs 512 samples (32ms) at 16kHz. If audio is at a higher rate
# (e.g. 44100 or 48000), the raw samples spanning one 32ms window are linearly
# resampled to exactly 512 (integer decimation of 44100 would give 14700Hz).
# Accumulator holds raw (pre-resample) samples; window_bytes reflects this.

namespace eval ::vad::silero {
    variable model ""
    variable request ""
    variable state {}           ;# [2,1,128] = 256 floats, frozen during silence
    variable accumulator ""     ;# binary int16 accumulator (raw sample rate)
    variable initialized 0
    variable threshold 0.5
    variable end_threshold 0.35 ;# min prob to commit LSTM state update

    # Fixed model input: 512 samples at 16kHz = 32ms
    variable window_samples 512

    # Set by init based on actual sample rate
    variable raw_per_window 512 ;# raw input samples spanning one 16kHz window
    variable window_bytes 1024  ;# raw_per_window * 2 bytes

    # Last actual inference result; returned during accumulation so callers
    # see a stable probability and don't mistake "not ready yet" for speech.
    variable last_prob -1.0

    proc init {model_path {device CPU} {threshold_val 0.5} {sample_rate 16000} {end_threshold_val 0.35}} {
        variable model
        variable request
        variable state
        variable accumulator
        variable initialized
        variable threshold
        variable end_threshold
        variable window_samples
        variable raw_per_window
        variable window_bytes

        set threshold $threshold_val
        set end_threshold $end_threshold_val

        # Silero needs exactly window_samples at 16kHz. 44100/48000 are not
        # integer multiples of 16000, so accumulate the raw samples spanning one
        # 32ms window and linearly resample them to window_samples (see process).
        set raw_per_window [expr {max($window_samples, round($window_samples * $sample_rate / 16000.0))}]
        set window_bytes [expr {$raw_per_window * 2}]
        if {$raw_per_window != $window_samples} {
            puts stderr "vad::silero: ${sample_rate}Hz input, resampling ${raw_per_window}→${window_samples} samples/window (→16kHz)"
        }

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

    # Convert binary int16 PCM bytes to a list of exactly `out_n` normalized
    # f32 values [-1,1], linearly resampling from however many input samples are
    # present. This gives a true 16kHz window (integer decimation of 44100 would
    # yield 14700Hz and skew the model).
    proc _resample_to_float {bytes out_n} {
        binary scan $bytes s* samples
        set in_n [llength $samples]
        if {$in_n == $out_n} {
            return [lmap s $samples {expr {$s / 32768.0}}]
        }
        set out {}
        set ratio [expr {double($in_n - 1) / ($out_n - 1)}]
        for {set j 0} {$j < $out_n} {incr j} {
            set pos [expr {$j * $ratio}]
            set i0  [expr {int($pos)}]
            set i1  [expr {$i0 + 1 < $in_n ? $i0 + 1 : $i0}]
            set frac [expr {$pos - $i0}]
            set s0 [lindex $samples $i0]
            set s1 [lindex $samples $i1]
            lappend out [expr {($s0 + ($s1 - $s0) * $frac) / 32768.0}]
        }
        return $out
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
        variable last_prob
        variable end_threshold

        if {!$initialized} { return -1.0 }

        append accumulator $int16_data

        # Not enough data yet — return last known prob so callers see a stable
        # decision rather than -1, which would be misread as "speech" and reset
        # the silence timer. Only -1.0 on the very first window before any result.
        if {[string length $accumulator] < $window_bytes} {
            return $last_prob
        }

        # Extract one window, keep remainder
        set window [string range $accumulator 0 [expr {$window_bytes - 1}]]
        set accumulator [string range $accumulator $window_bytes end]

        # Convert int16 → float list, resampling to exactly window_samples @16kHz
        set audio_floats [_resample_to_float $window $window_samples]

        # Run inference
        $request set_input 0 $audio_floats -type f32 -shape [list 1 $window_samples]
        $request set_input 2 $state -type f32 -shape {2 1 128}
        $request infer

        # Read speech probability
        set out [$request get_output 0]
        set prob [lindex [dict get $out data] 0]

        # Only commit LSTM state when speech is present (prob >= end_threshold).
        # During silence, state is frozen so it can't drift toward silence-bias
        # over long quiet periods between utterances.
        if {$prob >= $end_threshold} {
            set state_out [$request get_output 1]
            set state [dict get $state_out data]
        }

        set last_prob $prob
        return $prob
    }

    # Clear the sample accumulator and last_prob without touching LSTM state.
    # Call when audio has been discontinuous (e.g. after backlog skip) to avoid
    # feeding a window that mixes old and new audio to the model.
    proc flush_accumulator {} {
        variable accumulator
        variable last_prob
        set accumulator ""
        set last_prob -1.0
    }

    # Reset LSTM state and accumulator (call at utterance boundaries)
    proc reset {} {
        variable state
        variable accumulator
        variable last_prob
        set state [lrepeat 256 0.0]
        set accumulator ""
        set last_prob -1.0
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
