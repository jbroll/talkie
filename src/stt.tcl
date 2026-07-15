# stt.tcl - Common STT engine dispatch.
#
# One place branches critcl (in-process) vs coprocess (side-service) so the
# rest of engine.tcl speaks a single verb set. Every engine backend meets
# this contract:
#   create  -> handle
#   process -> dict {partial <str> endpoint 0|1}
#   final   -> dict {text <str>}
#   reset   -> ok
#   destroy -> {}
package require json

namespace eval ::stt {}

# Create a recognizer handle for an engine.
#   type: "critcl" | "coprocess"
#   cfg : config dict (array get) used to pass engine tuning knobs
proc ::stt::create {engine_name type model_path rate {cfg {}}} {
    switch -- $type {
        critcl {
            switch -- $engine_name {
                vosk {
                    package require vosk
                    if {[info commands vosk::set_log_level] ne ""} { vosk::set_log_level -1 }
                    set m [vosk::load_model -path $model_path]
                    return [$m create_recognizer -rate $rate -alternatives 1]
                }
                sherpa-onnx {
                    package require sherpa
                    # Auto-detect model kind (streaming/offline transducer, or CTC).
                    # Only options accepted by all three recognizers are forwarded.
                    set opts [list -rate $rate]
                    foreach {key flag} {
                        sherpa_num_threads -num-threads
                        sherpa_provider    -provider
                    } {
                        if {[dict exists $cfg $key]} { lappend opts $flag [dict get $cfg $key] }
                    }
                    return [sherpa::load_auto -path $model_path {*}$opts]
                }
                default { error "::stt::create: unknown critcl engine $engine_name" }
            }
        }
        coprocess {
            set cmd [::engine::get_property $engine_name command]
            return [::coprocess::start $engine_name $cmd $model_path $rate]
        }
        default { error "::stt::create: unknown type $type" }
    }
}

# Normalize a process result to dict {partial <s> endpoint 0|1}.
# sherpa-onnx returns a native Tcl dict (has an 'endpoint' key); vosk and
# coprocess engines return a JSON string without one.
proc ::stt::_normalize_partial {raw} {
    if {![catch {dict exists $raw endpoint} has] && $has} {
        return [list partial [expr {[dict exists $raw partial] ? [dict get $raw partial] : ""}] \
                     endpoint [dict get $raw endpoint]]
    }
    set d [json::json2dict $raw]
    return [list partial  [expr {[dict exists $d partial]  ? [dict get $d partial]  : ""}] \
                 endpoint [expr {[dict exists $d endpoint] ? [dict get $d endpoint] : 0}]]
}

proc ::stt::process {handle type chunk} {
    switch -- $type {
        critcl    { return [::stt::_normalize_partial [$handle process $chunk]] }
        coprocess { return [::stt::_normalize_partial [::coprocess::process $handle $chunk]] }
    }
}

# Finalize the utterance. Returns dict {text <s> confidence <0-100>}.
# Confidence is utterance-level: vosk (alternatives mode) reports it directly;
# engines without a confidence (sherpa-onnx) return 100 (never filtered).
proc ::stt::final {handle type} {
    switch -- $type {
        critcl    { set raw [$handle final-result] }
        coprocess { set raw [::coprocess::final $handle] }
    }
    # sherpa-onnx returns a native Tcl dict {text ...}; no confidence.
    if {![catch {dict exists $raw text} has] && $has} {
        return [list text [dict get $raw text] confidence 100]
    }
    # vosk / coprocess return JSON.
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

proc ::stt::reset {handle type} {
    switch -- $type {
        critcl    { $handle reset }
        coprocess { ::coprocess::reset $handle }
    }
    return ok
}

proc ::stt::destroy {handle type} {
    switch -- $type {
        critcl    { catch {$handle close} }
        coprocess { ::coprocess::stop $handle }
    }
    return ""
}
