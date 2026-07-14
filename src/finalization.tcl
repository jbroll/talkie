# finalization.tcl - capability-driven end-of-utterance decision.
#
# Extracted as pure logic so it is unit-testable without audio or threads.
# Used by the processing worker to decide when to finalize a segment.

namespace eval ::engine {}

# Decide whether the current utterance should be finalized.
#   self_endpoint          : 1 if the engine self-detects end-of-utterance
#   endpoint               : engine's endpoint flag this chunk (0|1)
#   partial_changed        : 1 if the partial text changed this chunk (reserved)
#   silence_elapsed        : seconds since last speech (energy VAD)
#   silence_seconds        : configured energy-silence timeout
#   stable_elapsed         : seconds since the partial last changed
#   partial_stable_seconds : configured partial-stability timeout
#
# self-endpoint engines (sherpa-onnx) defer entirely to the recognizer.
# external engines (whisper.cpp, OpenVINO GenAI, energy-VAD Vosk) finalize on
# energy-silence OR partial-stability, whichever fires first.
proc ::engine::should_finalize {self_endpoint endpoint partial_changed \
        silence_elapsed silence_seconds stable_elapsed partial_stable_seconds} {
    if {$self_endpoint} {
        return [expr {$endpoint ? 1 : 0}]
    }
    if {$silence_elapsed > $silence_seconds} { return 1 }
    if {$stable_elapsed  > $partial_stable_seconds} { return 1 }
    return 0
}
