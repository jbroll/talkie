proc config_init {} {
    set ::transcribing [state_load]

    config_load
    config_trace
    state_file_watcher

    ::audio::refresh_devices
    ::output::initialize
    ::audio::initialize

    config_refresh_models

    # Initial typing delay is set during output thread initialization
    # No need to set it again here
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
        window_x                   100
        window_y                   100
        initialization_samples     50
        spike_suppression_seconds  0.3
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
    trace add variable ::config(typing_delay_ms) write config_typing_delay_change
    trace add variable ::config(input_device) write config_input_device_change
    trace add variable ::transcribing write state_transcribing_change
}

proc config_engine_change {args} {
    # Hot-swap engine without restart
    # Stop transcription first to avoid race conditions
    set was_transcribing $::transcribing
    if {$was_transcribing} {
        set ::transcribing false
        after 100  ;# Give audio callback time to finish
    }

    ::engine::cleanup
    ::engine::initialize

    # Restore transcription state if it was active
    if {$was_transcribing} {
        set ::transcribing true
    }
}

proc config_model_change {args} {
    # Stop transcription during model change
    set was_transcribing $::transcribing
    if {$was_transcribing} {
        set ::transcribing false
        after 100  ;# Give audio callback time to finish
    }

    ::engine::cleanup
    ::engine::initialize

    # Restore transcription state
    if {$was_transcribing} {
        set ::transcribing true
    }
}

proc config_typing_delay_change {args} {
    if {[info exists ::config(typing_delay_ms)]} {
        ::output::set_typing_delay $::config(typing_delay_ms)
    }
}

proc config_input_device_change {args} {
    # Hot-swap audio input device without restart
    set was_transcribing $::transcribing
    if {$was_transcribing} {
        set ::transcribing false
        after 100  ;# Give audio callback time to finish
    }

    ::audio::restart_audio_stream

    # Restore transcription state
    if {$was_transcribing} {
        set ::transcribing true
    }
}

proc state_transcribing_change {args} {
    # Protect against errors during engine switching
    if {[catch {
        if {$::transcribing} {
            ::audio::start_transcription
        } else {
            ::audio::stop_transcription
        }
    } err]} {
        # Silently ignore errors during engine switch
        # This happens when recognizer is empty during cleanup
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
