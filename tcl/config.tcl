# config.tcl - Configuration management for Talkie

package require json

namespace eval ::config {
    # Default configuration - ui-layout.tcl expects global ::config array
    # so we set up defaults and copy to global scope

    proc config_file {} {
        expr {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""
            ? [file join $::env(XDG_CONFIG_HOME) talkie.conf]
            : [file join $::env(HOME) .talkie.conf]}
    }

    proc save {args} {
        if {[catch {
            echo [json::dict2json [array get ::config]] > [config_file]
        } err]} {
            puts "CONFIG: Error saving: $err"
        }
    }

    proc load {} {
        # Set defaults matching ui-layout.tcl requirements
        array set ::config {
            input_device          "pulse"
            energy_threshold       20
            confidence_threshold  175
            lookback_seconds        1.5
            silence_seconds         1.5
            vosk_beam              20
            vosk_lattice            8
            vosk_alternatives       1
            sample_rate           44100
            frames_per_buffer     4410
            window_x               100
            window_y               100
            device               "pulse"
            model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
            vosk_max_alternatives    0
            vosk_lattice_beam        8
        }

        set file [config_file]
        if {![file exists $file]} {
            save
            return
        }

        if {[catch {
            array set ::config [json::json2dict [cat $file]]
        } err]} {
            puts "CONFIG: Error loading: $err"
        }
    }

    # Simple accessors
    proc get {key} {
        return $::config($key)
    }

    # Setup auto-save trace after array initialization
    proc setup_trace {} {
        # Add trace to each config element for auto-save
        foreach key [array names ::config] {
            trace add variable ::config($key) write ::config::save
        }
    }

    proc state_file {} {
        return [file join $::env(HOME) .talkie]
    }

    proc load_state {} {
        if {[file exists [state_file]]} {
            set state_dict [json::json2dict [cat [state_file]]]
            set transcribing [dict get $state_dict transcribing]
            # Convert boolean to integer if needed
            if {$transcribing eq "true"} {
                return 1
            } elseif {$transcribing eq "false"} {
                return 0
            } else {
                return $transcribing
            }
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
