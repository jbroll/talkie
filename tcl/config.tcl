# config.tcl - Configuration management for Talkie
package require json

namespace eval ::config {
    variable defaults
    variable current

    array set defaults {
        sample_rate 44100
        frames_per_buffer 4410
        energy_threshold 5.0
        confidence_threshold 200.0
        window_x 100
        window_y 100
        device "pulse"
        model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
        silence_trailing_duration 0.5
        lookback_duration 1.0
        lookback_frames 10
        vosk_max_alternatives 0
        vosk_beam 20
        vosk_lattice_beam 8
    }

    # Initialize current config with defaults
    array set current [array get defaults]

    # Initialize lookback_frames based on lookback_duration
    set current(lookback_frames) [expr {int($current(lookback_duration) * 10 + 0.5)}]

    proc get_config_file_path {} {
        if {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""} {
            set config_dir $::env(XDG_CONFIG_HOME)
            file mkdir $config_dir
            return [file join $config_dir talkie.conf]
        } else {
            return [file join $::env(HOME) .talkie.conf]
        }
    }

    proc load {} {
        variable current

        set config_file [get_config_file_path]

        if {[file exists $config_file]} {
            if {[catch {
                set fp [open $config_file r]
                set json_data [read $fp]
                close $fp

                # Parse JSON and update config array
                set config_dict [json::json2dict $json_data]
                dict for {key value} $config_dict {
                    set current($key) $value
                }
            } err]} {
                puts "CONFIG: Error loading config: $err"
            }
        } else {
            # Create default config file
            save
        }

        # Recalculate lookback_frames based on loaded lookback_duration
        set current(lookback_frames) [expr {int($current(lookback_duration) * 10 + 0.5)}]
    }

    proc save {} {
        variable current

        set config_file [get_config_file_path]

        if {[catch {
            set json_data "{\n"
            set first true
            foreach key [lsort [array names current]] {
                if {!$first} {
                    append json_data ",\n"
                }
                set first false

                # Format value based on type
                set value $current($key)
                if {[string is double -strict $value]} {
                    append json_data "  \"$key\": $value"
                } elseif {[string is integer -strict $value]} {
                    append json_data "  \"$key\": $value"
                } elseif {[string is boolean -strict $value]} {
                    append json_data "  \"$key\": [expr {$value ? "true" : "false"}]"
                } else {
                    # String value - escape quotes
                    set escaped_value [string map {\" \\\"} $value]
                    append json_data "  \"$key\": \"$escaped_value\""
                }
            }
            append json_data "\n}"

            set fp [open $config_file w]
            puts $fp $json_data
            close $fp

        } err]} {
            puts "CONFIG: Error saving config: $err"
        }
    }

    proc get {key} {
        variable current
        return $current($key)
    }

    proc set_value {key value} {
        variable current
        set current($key) $value
    }

    proc update_param {key value} {
        variable current
        set current($key) $value
        save
    }

    proc get_all {} {
        variable current
        return [array get current]
    }
}

# Provide global config compatibility
proc get_config_file_path {} {
    return [::config::get_config_file_path]
}

proc load_config {} {
    ::config::load
}

proc save_config {} {
    ::config::save
}

proc update_config_param {key value} {
    ::config::update_param $key $value
}