# finalization.tcl - capability-driven end-of-utterance decision.
#
# Extracted as pure logic so it is unit-testable without audio or threads.
# Used by the processing worker to decide when to finalize a segment.

namespace eval ::engine {}

# Decide whether the current utterance should be finalized.
#   self_endpoint          : 1 if the engine self-detects end-of-utterance
#   endpoint               : engine's endpoint flag this chunk (0|1)
#   have_partial           : 1 if a non-empty partial has been produced
#   silence_elapsed        : seconds since last speech (energy/VAD)
#   silence_seconds        : configured energy-silence timeout
#   stable_elapsed         : seconds since the partial last changed
#   partial_stable_seconds : partial-stability timeout (<= 0 disables it)
#
# self-endpoint engines (sherpa-onnx) defer entirely to the recognizer.
# external engines (whisper.cpp, OpenVINO GenAI, Vosk) finalize on energy/VAD
# silence OR, when enabled, a non-empty partial staying stable — whichever
# fires first. Partial-stability only applies once a real partial exists and
# partial_stable_seconds > 0, so it can never fire on an empty segment.
proc ::engine::should_finalize {self_endpoint endpoint have_partial \
        silence_elapsed silence_seconds stable_elapsed partial_stable_seconds} {
    if {$self_endpoint} {
        return [expr {$endpoint ? 1 : 0}]
    }
    if {$silence_elapsed > $silence_seconds} { return 1 }
    if {$have_partial && $partial_stable_seconds > 0 && $stable_elapsed > $partial_stable_seconds} {
        return 1
    }
    return 0
}
