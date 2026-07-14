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

namespace eval stt {}

# Create a recognizer handle for an engine.
#   type: "critcl" | "coprocess"
proc stt::create {engine_name type model_path rate} {
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
                    return [sherpa::load_model -path $model_path -rate $rate]
                }
                default { error "stt::create: unknown critcl engine $engine_name" }
            }
        }
        coprocess {
            set cmd [::engine::get_property $engine_name command]
            return [::coprocess::start $engine_name $cmd $model_path $rate]
        }
        default { error "stt::create: unknown type $type" }
    }
}

# Normalize a process result to dict {partial <s> endpoint 0|1}.
# sherpa-onnx returns a native Tcl dict (has an 'endpoint' key); vosk and
# coprocess engines return a JSON string without one.
proc stt::_normalize_partial {raw} {
    if {![catch {dict exists $raw endpoint} has] && $has} {
        return [list partial [expr {[dict exists $raw partial] ? [dict get $raw partial] : ""}] \
                     endpoint [dict get $raw endpoint]]
    }
    set d [json::json2dict $raw]
    return [list partial  [expr {[dict exists $d partial]  ? [dict get $d partial]  : ""}] \
                 endpoint [expr {[dict exists $d endpoint] ? [dict get $d endpoint] : 0}]]
}

proc stt::process {handle type chunk} {
    switch -- $type {
        critcl    { return [stt::_normalize_partial [$handle process $chunk]] }
        coprocess { return [stt::_normalize_partial [::coprocess::process $handle $chunk]] }
    }
}

proc stt::final {handle type} {
    switch -- $type {
        critcl    { set raw [$handle final-result] }
        coprocess { set raw [::coprocess::final $handle] }
    }
    if {![catch {dict exists $raw text} has] && $has} { return [list text [dict get $raw text]] }
    set d [json::json2dict $raw]
    return [list text [expr {[dict exists $d text] ? [dict get $d text] : ""}]]
}

# Final result as a JSON string for the GEC worker.
# vosk/coprocess already return rich JSON (with word-level confidence) — pass
# it through untouched. sherpa-onnx returns a native Tcl dict — convert to JSON.
proc stt::final_json {handle type} {
    switch -- $type {
        critcl    { set raw [$handle final-result] }
        coprocess { set raw [::coprocess::final $handle] }
    }
    if {[string index [string trimleft $raw] 0] eq "\{"} { return $raw }
    return [json::dict2json $raw]
}

proc stt::reset {handle type} {
    switch -- $type {
        critcl    { $handle reset }
        coprocess { ::coprocess::reset $handle }
    }
    return ok
}

proc stt::destroy {handle type} {
    switch -- $type {
        critcl    { catch {$handle close} }
        coprocess { ::coprocess::stop $handle }
    }
    return ""
}
