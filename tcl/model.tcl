# model.tcl - Model management for Talkie

namespace eval ::model {
    proc refresh_models {} {
        set models_dir [file join [file dirname $::script_dir] models vosk]
        set ::model_files [lsort [lmap item [glob -nocomplain -directory $models_dir -type d *] {file tail $item}]]
    }

    proc get_model_path {modelfile} {
        return [file join [file dirname $::script_dir] models vosk $modelfile]
    }
}
