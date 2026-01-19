# threshold.tcl - Confidence threshold filtering
# VAD (voice activity detection) logic is now in engine.tcl worker thread

namespace eval ::threshold {
    # Accept or reject a recognition result based on confidence
    proc accept {conf} {
        set threshold $::config(confidence_threshold)
        set accepted [expr {$conf >= $threshold}]

        if {$accepted} {
            puts "THRS-ACCEPT: $conf >= $threshold"
        } else {
            puts "THRS-FILTER: $conf < $threshold"
        }

        return $accepted
    }
}
