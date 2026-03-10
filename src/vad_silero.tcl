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
# (e.g. 44100 or 48000), samples are decimated by factor N = round(rate/16000).
# Accumulator holds raw (pre-decimation) samples; window_bytes reflects this.

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
    variable decimate   1       ;# decimation factor (1 = no decimation)
    variable window_bytes 1024  ;# window_samples * decimate * 2 bytes

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
        variable decimate
        variable window_bytes

        set threshold $threshold_val
        set end_threshold $end_threshold_val

        # Compute decimation factor so we always feed 32ms worth of audio
        set decimate [expr {max(1, round($sample_rate / 16000.0))}]
        set window_bytes [expr {$window_samples * $decimate * 2}]
        if {$decimate > 1} {
            puts stderr "vad::silero: ${sample_rate}Hz input, decimating by $decimate → 16kHz"
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

    # Convert binary int16 PCM bytes to list of normalized f32 values [-1,1],
    # decimating by factor N (keeping every Nth sample).
    proc _to_float {bytes {N 1}} {
        binary scan $bytes s* samples
        if {$N == 1} {
            return [lmap s $samples {expr {$s / 32768.0}}]
        }
        set out {}
        set i 0
        foreach s $samples {
            if {$i % $N == 0} { lappend out [expr {$s / 32768.0}] }
            incr i
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
        variable decimate
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

        # Convert int16 → float list, decimating to 16kHz
        set audio_floats [_to_float $window $decimate]

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
