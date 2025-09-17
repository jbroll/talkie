namespace eval ::config {
    proc config_file {} {
        expr {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""
            ? [file join $::env(XDG_CONFIG_HOME) talkie.conf]
            : [file join $::env(HOME) .talkie.conf]}
    }

    proc save {args} {
        echo [json::dict2json [array get ::config]] > [config_file]
    }

    proc load {} {
        array set ::config [list {*}{
            sample_rate           44100
            frames_per_buffer     4410
            window_x               100
            window_y               100
        } {*}[array get ::config]]

        set file [config_file]
        if {![file exists $file]} {
            save
            return
        }

        array set ::config [json::json2dict [cat $file]]
    }

    proc setup_trace {} {
        trace add variable ::config write ::config::save
        trace add variable ::config(vosk_modelfile) write ::config::handle_model_change
    }

    proc handle_model_change {args} {
        ::vosk::cleanup
        ::vosk::initialize
    }

    proc state_file {} {
        return [file join $::env(HOME) .talkie]
    }

    proc load_state {} {
        if {[file exists [state_file]]} {
            set state_dict [json::json2dict [cat [state_file]]]
            set transcribing [expr { !![dict get $state_dict transcribing]}]
        } else {
            return 0
        }
    }

    proc save_state {transcribing} {
        echo [json::dict2json [dict create transcribing $transcribing]] > [state_file]
    }

    proc setup_file_watcher {} {
        filewatch [state_file] {set ::transcribing [::config::load_state]} 500
    }
}
