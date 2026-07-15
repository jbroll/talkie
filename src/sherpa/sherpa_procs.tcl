# sherpa_procs.tcl - runtime Tcl helpers bundled with the sherpa package.

# Resolve standard streaming-Zipformer file names from a model directory,
# then construct a recognizer. -path is the model directory; -rate optional.
proc sherpa::load_model {args} {
    array set opt {-rate 16000}
    array set opt $args
    set dir $opt(-path); unset opt(-path)
    set enc [lindex [glob -nocomplain -directory $dir encoder-*.int8.onnx] 0]
    set dec [lindex [glob -nocomplain -directory $dir decoder-*.int8.onnx] 0]
    set joi [lindex [glob -nocomplain -directory $dir joiner-*.int8.onnx] 0]
    set tok [file join $dir tokens.txt]
    foreach {name val} [list encoder $enc decoder $dec joiner $joi tokens $tok] {
        if {$val eq "" || ![file exists $val]} { error "sherpa::load_model: missing $name in $dir" }
    }
    # Forward every remaining option (-rate, -max-active-paths, -rule*, ...).
    return [sherpa::create_recognizer -encoder $enc -decoder $dec -joiner $joi -tokens $tok {*}[array get opt]]
}

# Detect the kind of sherpa-onnx model in a directory:
#   online-transducer  - streaming Zipformer (encoder/decoder/joiner, "chunk"/"streaming")
#   offline-transducer - non-streaming transducer (encoder/decoder/joiner)
#   offline-ctc        - single-file CTC model (NeMo/Zipformer/WeNet)
proc sherpa::detect_kind {dir} {
    # Name markers first (sherpa-onnx model dirs are consistently named); these
    # architectures are otherwise ambiguous by file layout alone.
    set name [string tolower [file tail $dir]]
    if {[string match *sense-voice* $name] || [string match *sensevoice* $name]} { return sense-voice }
    if {[string match *moonshine* $name]} { return moonshine }
    if {[string match *whisper* $name]}   { return whisper }
    # (canary added in its own turn)

    set has_enc [expr {[llength [glob -nocomplain -directory $dir encoder*.onnx]] > 0}]
    set has_joi [expr {[llength [glob -nocomplain -directory $dir joiner*.onnx]] > 0}]
    if {!($has_enc && $has_joi)} { return offline-ctc }
    set encname [file tail [lindex [glob -nocomplain -directory $dir encoder*.onnx] 0]]
    if {[string match -nocase *streaming* $name] || [string match *chunk* $encname]} {
        return online-transducer
    }
    return offline-transducer
}

# 1 if the model in $dir is a streaming (self-endpointing) recognizer.
proc sherpa::is_self_endpoint {dir} {
    return [expr {[sherpa::detect_kind $dir] eq "online-transducer"}]
}

# Load whichever recognizer the model directory calls for. -path is the model
# dir; remaining options (-rate/-num-threads/-provider) forward to the loader.
proc sherpa::load_auto {args} {
    array set opt $args
    switch -- [sherpa::detect_kind $opt(-path)] {
        online-transducer  { return [sherpa::load_model {*}$args] }
        offline-transducer { return [sherpa::load_offline_model {*}$args] }
        offline-ctc        { return [sherpa::load_offline_ctc_model {*}$args] }
        sense-voice        { return [sherpa::load_sensevoice_model {*}$args] }
        moonshine          { return [sherpa::load_moonshine_model {*}$args] }
        whisper            { return [sherpa::load_whisper_model {*}$args] }
    }
}

# Pick a model file by base name, preferring an int8 variant.
proc sherpa::_pick_onnx {dir base} {
    set i8 [lindex [lsort [glob -nocomplain -directory $dir ${base}*int8*.onnx]] 0]
    if {$i8 ne ""} { return $i8 }
    return [lindex [lsort [glob -nocomplain -directory $dir ${base}*.onnx]] 0]
}

# Offline (non-streaming) transducer model: Parakeet, offline Zipformer, etc.
# -path is the model directory; other options forward to create_offline_recognizer.
proc sherpa::load_offline_model {args} {
    array set opt {-rate 16000}
    array set opt $args
    set dir $opt(-path); unset opt(-path)
    set enc [sherpa::_pick_onnx $dir encoder]
    set dec [sherpa::_pick_onnx $dir decoder]
    set joi [sherpa::_pick_onnx $dir joiner]
    set tok [file join $dir tokens.txt]
    foreach {name val} [list encoder $enc decoder $dec joiner $joi tokens $tok] {
        if {$val eq "" || ![file exists $val]} { error "sherpa::load_offline_model: missing $name in $dir" }
    }
    return [sherpa::create_offline_recognizer -encoder $enc -decoder $dec -joiner $joi -tokens $tok {*}[array get opt]]
}

# Offline CTC model (single ONNX file): NeMo/Zipformer/WeNet CTC.
proc sherpa::load_offline_ctc_model {args} {
    array set opt {-rate 16000}
    array set opt $args
    set dir $opt(-path); unset opt(-path)
    set model [sherpa::_pick_onnx $dir model]
    if {$model eq ""} {
        set model [lindex [lsort [glob -nocomplain -directory $dir *int8*.onnx]] 0]
        if {$model eq ""} { set model [lindex [lsort [glob -nocomplain -directory $dir *.onnx]] 0] }
    }
    set tok [file join $dir tokens.txt]
    foreach {name val} [list model $model tokens $tok] {
        if {$val eq "" || ![file exists $val]} { error "sherpa::load_offline_ctc_model: missing $name in $dir" }
    }
    return [sherpa::create_offline_ctc_recognizer -model $model -tokens $tok {*}[array get opt]]
}

# SenseVoice model (single ONNX file): multilingual, fast, ITN.
proc sherpa::load_sensevoice_model {args} {
    array set opt {-rate 16000}
    array set opt $args
    set dir $opt(-path); unset opt(-path)
    set model [sherpa::_pick_onnx $dir model]
    if {$model eq ""} { set model [lindex [lsort [glob -nocomplain -directory $dir *.onnx]] 0] }
    set tok [file join $dir tokens.txt]
    foreach {name val} [list model $model tokens $tok] {
        if {$val eq "" || ![file exists $val]} { error "sherpa::load_sensevoice_model: missing $name in $dir" }
    }
    return [sherpa::create_offline_sensevoice_recognizer -model $model -tokens $tok {*}[array get opt]]
}

# Moonshine model (preprocessor + encoder + uncached/cached decoders).
proc sherpa::load_moonshine_model {args} {
    array set opt {-rate 16000}
    array set opt $args
    set dir $opt(-path); unset opt(-path)
    set pre [sherpa::_pick_onnx $dir preprocess]
    set enc [sherpa::_pick_onnx $dir encode]
    set unc [sherpa::_pick_onnx $dir uncached_decode]
    set cac [sherpa::_pick_onnx $dir cached_decode]
    set tok [file join $dir tokens.txt]
    foreach {name val} [list preprocessor $pre encoder $enc uncached_decoder $unc cached_decoder $cac tokens $tok] {
        if {$val eq "" || ![file exists $val]} { error "sherpa::load_moonshine_model: missing $name in $dir" }
    }
    return [sherpa::create_offline_moonshine_recognizer -preprocessor $pre -encoder $enc \
        -uncached-decoder $unc -cached-decoder $cac -tokens $tok {*}[array get opt]]
}

# Whisper model (encoder + decoder). Tokens file is named "<prefix>-tokens.txt".
proc sherpa::load_whisper_model {args} {
    array set opt {-rate 16000}
    array set opt $args
    set dir $opt(-path); unset opt(-path)
    set enc [lindex [lsort [glob -nocomplain -directory $dir *encoder*int8*.onnx]] 0]
    if {$enc eq ""} { set enc [lindex [lsort [glob -nocomplain -directory $dir *encoder*.onnx]] 0] }
    set dec [lindex [lsort [glob -nocomplain -directory $dir *decoder*int8*.onnx]] 0]
    if {$dec eq ""} { set dec [lindex [lsort [glob -nocomplain -directory $dir *decoder*.onnx]] 0] }
    set tok [lindex [glob -nocomplain -directory $dir *tokens.txt] 0]
    foreach {name val} [list encoder $enc decoder $dec tokens $tok] {
        if {$val eq "" || ![file exists $val]} { error "sherpa::load_whisper_model: missing $name in $dir" }
    }
    return [sherpa::create_offline_whisper_recognizer -encoder $enc -decoder $dec -tokens $tok {*}[array get opt]]
}
