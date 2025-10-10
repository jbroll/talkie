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
        window_x               100
        window_y               100
        initialization_samples 100
    } {*}[array get ::config]]

    set file [config_file]
    if {![file exists $file]} {
        config_save
        return
    }

    array set ::config [json::json2dict [cat $file]]
}

proc config_refresh_models {} {
    # Refresh model lists for both engines
    set vosk_dir [file join [file dirname $::script_dir] models vosk]
    set sherpa_dir [file join [file dirname $::script_dir] models sherpa-onnx]

    set ::vosk_model_files [lsort [lmap item [glob -nocomplain -directory $vosk_dir -type d *] {file tail $item}]]
    set ::sherpa_model_files [lsort [lmap item [glob -nocomplain -directory $sherpa_dir -type d *] {file tail $item}]]

    # Legacy: keep ::model_files for backwards compatibility
    if {$::config(speech_engine) eq "vosk"} {
        set ::model_files $::vosk_model_files
    } else {
        set ::model_files $::sherpa_model_files
    }
}

proc config_trace {} {
    trace add variable ::config write config_save
    trace add variable ::config(speech_engine) write config_engine_change
    trace add variable ::config(vosk_modelfile) write config_model_change
    trace add variable ::config(sherpa_modelfile) write config_model_change
    trace add variable ::transcribing write state_transcribing_change
}

proc config_engine_change {args} {
    # Prevent recursion during revert
    if {[info exists ::reverting_engine] && $::reverting_engine} {
        return
    }

    # Only prompt if initial_engine is set (i.e., config dialog is open)
    if {![info exists ::initial_engine]} {
        return
    }

    # Only prompt if changing from initial value
    if {$::config(speech_engine) ne $::initial_engine} {
        set answer [tk_messageBox -type okcancel -icon warning \
            -title "Restart Required" \
            -message "Speech engine change requires restart.\n\nClick OK to restart now, or Cancel to revert."]

        if {$answer eq "ok"} {
            # Save config and exit with code 4 to signal restart
            config_save
            exit 4
        } else {
            # Revert change (with recursion protection)
            set ::reverting_engine 1
            set ::config(speech_engine) $::initial_engine
            set ::reverting_engine 0
        }
    }
}

proc config_model_change {args} {
    ::engine::cleanup
    ::engine::initialize
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
