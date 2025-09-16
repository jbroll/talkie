# config.tcl - Configuration management for Talkie

package require json

namespace eval ::config {
    # Configuration array - directly usable with Tk -variable
    variable config

    # Default configuration
    array set config {
        sample_rate 44100
        frames_per_buffer 4410
        energy_threshold 5.0
        confidence_threshold 200.0
        window_x 100
        window_y 100
        device "pulse"
        model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
        silence_trailing_duration 0.5
        lookback_seconds 1.0
        vosk_max_alternatives 0
        vosk_beam 20
        vosk_lattice_beam 8
    }

    proc config_file {} {
        expr {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""
            ? [file join $::env(XDG_CONFIG_HOME) talkie.conf]
            : [file join $::env(HOME) .talkie.conf]}
    }

    proc save {args} {
        variable config
        if {[catch {
            echo [json::dict2json [array get config]] > [config_file]
        } err]} {
            puts "CONFIG: Error saving: $err"
        }
    }

    proc load {} {
        variable config

        set file [config_file]
        if {![file exists $file]} {
            save
            return
        }

        if {[catch {
            array set config [json::json2dict [cat $file]]
        } err]} {
            puts "CONFIG: Error loading: $err"
        }
    }

    # Simple accessors
    proc get {key} {
        variable config
        return $config($key)
    }

    # Setup auto-save trace after array initialization
    proc setup_trace {} {
        variable config
        # Add trace to each config element for auto-save
        foreach key [array names config] {
            trace add variable config($key) write ::config::save
        }
    }

    proc state_file {} {
        return [file join $::env(HOME) .talkie]
    }

    proc load_state {} {
        expr {[file exists [state_file]] ? [dict get [json::json2dict [cat [state_file]]] transcribing] : false}
    }

    proc save_state {transcribing} {
        echo [json::dict2json [dict create transcribing $transcribing]] > [state_file]
    }

    proc setup_file_watcher {} {
        filewatch [state_file] {set ::transcribing [::config::load_state]} 500
    }
}
