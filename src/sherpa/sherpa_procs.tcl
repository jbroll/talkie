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
