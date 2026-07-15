# stt.tcl - Common STT engine dispatch (in-process critcl engines).
#
# Every engine backend meets this contract:
#   create  -> handle
#   process -> dict {partial <str> endpoint 0|1}
#   final   -> dict {text <str> confidence <0-100>}
#   reset   -> ok
#   destroy -> {}
package require json

namespace eval ::stt {}

# Create a recognizer handle for an engine.
#   cfg : config dict (array get) used to pass engine tuning knobs
proc ::stt::create {engine_name model_path rate {cfg {}}} {
    switch -- $engine_name {
        vosk {
            package require vosk
            if {[info commands vosk::set_log_level] ne ""} { vosk::set_log_level -1 }
            set m [vosk::load_model -path $model_path]
            return [$m create_recognizer -rate $rate -alternatives 1]
        }
        sherpa-onnx {
            package require sherpa
            # Auto-detect model kind (streaming/offline transducer, CTC, ...).
            set opts [list -rate $rate]
            foreach {key flag} {
                sherpa_num_threads -num-threads
                sherpa_provider    -provider
            } {
                if {[dict exists $cfg $key]} { lappend opts $flag [dict get $cfg $key] }
            }
            return [sherpa::load_auto -path $model_path {*}$opts]
        }
        default { error "::stt::create: unknown engine $engine_name" }
    }
}

# Normalize a process result to dict {partial <s> endpoint 0|1}.
# sherpa-onnx returns a native Tcl dict (has an 'endpoint' key); vosk returns JSON.
proc ::stt::_normalize_partial {raw} {
    if {![catch {dict exists $raw endpoint} has] && $has} {
        return [list partial [expr {[dict exists $raw partial] ? [dict get $raw partial] : ""}] \
                     endpoint [dict get $raw endpoint]]
    }
    set d [json::json2dict $raw]
    return [list partial  [expr {[dict exists $d partial]  ? [dict get $d partial]  : ""}] \
                 endpoint [expr {[dict exists $d endpoint] ? [dict get $d endpoint] : 0}]]
}

proc ::stt::process {handle chunk} {
    return [::stt::_normalize_partial [$handle process $chunk]]
}

# Finalize the utterance. Returns dict {text <s> confidence <0-100>}.
# Confidence is utterance-level: vosk (alternatives mode) reports it directly;
# engines without a confidence (sherpa-onnx) return 100 (never filtered).
proc ::stt::final {handle} {
    set raw [$handle final-result]
    # sherpa-onnx returns a native Tcl dict {text ...}; no confidence.
    if {![catch {dict exists $raw text} has] && $has} {
        return [list text [dict get $raw text] confidence 100]
    }
    # vosk returns JSON.
    set d [json::json2dict $raw]
    if {[dict exists $d alternatives]} {
        set alt [lindex [dict get $d alternatives] 0]
        set text [expr {[dict exists $alt text] ? [dict get $alt text] : ""}]
        set conf [expr {[dict exists $alt confidence] ? [dict get $alt confidence] : 100}]
    } else {
        set text [expr {[dict exists $d text] ? [dict get $d text] : ""}]
        set conf 100
    }
    if {$conf <= 1.0} { set conf [expr {$conf * 100}] }
    return [list text $text confidence $conf]
}

proc ::stt::reset {handle} {
    $handle reset
    return ok
}

proc ::stt::destroy {handle} {
    catch {$handle close}
    return ""
}
