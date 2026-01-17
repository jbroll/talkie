proc config_init {} {
    set ::transcribing [state_load]

    config_load
    config_trace
    state_file_watcher

    ::audio::refresh_devices
    ::output::initialize
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
        window_x                   100
        window_y                   100
        typing_delay_ms            5
        silence_seconds            0.3
        vosk_modelfile             vosk-model-en-us-0.22-lgraph
        initialization_samples     50
        speech_engine              vosk
        faster_whisper_modelfile   ""
        vosk_lattice               5
        min_duration               0.30
        noise_floor_percentile     10
        speech_min_multiplier      0.6
        sherpa_max_active_paths    4
        confidence_threshold       100
        sherpa_modelfile           sherpa-onnx-streaming-zipformer-en-2023-06-26
        speech_floor_percentile    70
        speech_max_multiplier      1.3
        spike_suppression_seconds  0.3
        lookback_seconds           0.5
        audio_threshold_multiplier 2.5
        vosk_beam                  10
        input_device               default
        max_confidence_penalty     75
        gec_homophone              1
        gec_punctcap               1
        gec_grammar                0
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
