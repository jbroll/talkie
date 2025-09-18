proc config_init {} {
    set ::transcribing [state_load]

    config_load
    config_trace
    state_file_watcher

    ::audio::refresh_devices
    ::audio::initialize

    config_refresh_models
}

proc config_file {} {
    expr {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""
        ? [file join $::env(XDG_CONFIG_HOME) talkie.conf]
        : [file join $::env(HOME) .talkie.conf]}
}

proc config_save {args} {
    echo [json::dict2json [array get ::config]] > [config_file]
}

proc config_load {} {
    array set ::config [list {*}{
        sample_rate           44100
        frames_per_buffer     4410
        window_x               100
        window_y               100
        initialization_samples 200
    } {*}[array get ::config]]

    set file [config_file]
    if {![file exists $file]} {
        save
        return
    }

    array set ::config [json::json2dict [cat $file]]
}

proc config_refresh_models {} {
    set models_dir [file join [file dirname $::script_dir] models vosk]
    set ::model_files [lsort [lmap item [glob -nocomplain -directory $models_dir -type d *] {file tail $item}]]
}

proc config_trace {} {
    trace add variable ::config write config_save
    trace add variable ::config(vosk_modelfile) write config_model_change
    trace add variable ::transcribing write state_transcribing_change
}

proc config_model_change {args} {
    ::vosk::cleanup
    ::vosk::initialize
}

proc state_transcribing_change {args} {
    if {$::transcribing} {
        ::audio::start_transcription
    } else {
        ::audio::stop_transcription
    }
}


proc state_file {} {
    return [file join $::env(HOME) .talkie]
}

proc state_load {} {
    if {[file exists [state_file]]} {
        set state_dict [json::json2dict [cat [state_file]]]
        set transcribing [expr { !![dict get $state_dict transcribing]}]
    } else {
        return 0
    }
}

proc state_save {transcribing} {
    echo [json::dict2json [dict create transcribing $transcribing]] > [state_file]
}

proc state_file_watcher {} {
    filewatch [state_file] {set ::transcribing [state_load]} 500
}
