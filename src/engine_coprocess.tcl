# engine_coprocess.tcl - Coprocess-based engine implementation
# Creates recognizer commands that wrap coprocess communication

source coprocess.tcl

namespace eval ::engine {
    variable recognizer_cmd ""
    variable engine_name ""

    # Create a recognizer command that wraps the coprocess
    proc create_recognizer_cmd {engine_name} {
        set cmd_name "::recognizer_${engine_name}"

        # Create the recognizer command
        proc $cmd_name {method args} [format {
            set engine_name "%s"

            switch $method {
                "process" {
                    # Process audio chunk - returns JSON
                    set audio_data [lindex $args 0]
                    return [::coprocess::process $engine_name $audio_data]
                }
                "final-result" {
                    # Get final result - returns JSON
                    return [::coprocess::final $engine_name]
                }
                "reset" {
                    # Reset recognizer - returns JSON
                    ::coprocess::reset $engine_name
                    return
                }
                "close" {
                    # Cleanup
                    ::coprocess::stop $engine_name
                    rename %s ""
                    return
                }
                default {
                    error "Unknown method: $method"
                }
            }
        } $engine_name $cmd_name]

        return $cmd_name
    }

    # Initialize engine and return recognizer command
    proc initialize {} {
        variable recognizer_cmd
        variable engine_name

        set engine_name $::config(speech_engine)

        # Engine configurations
        array set engine_config {
            vosk,command           "python3 engines/vosk_engine.py"
            vosk,type              "streaming"
            faster-whisper,command "engines/faster_whisper_wrapper.sh"
            faster-whisper,type    "batch"
        }

        if {![info exists engine_config($engine_name,command)]} {
            puts "ERROR: Unknown engine: $engine_name"
            return false
        }

        set cmd $engine_config($engine_name,command)
        set model_path [get_model_path]

        puts "Starting $engine_name engine..."
        puts "  Command: $cmd"
        puts "  Model: $model_path"
        puts "  Sample rate: $::device_sample_rate"

        # Start coprocess
        set response [::coprocess::start $engine_name $cmd $model_path $::device_sample_rate]

        # Parse JSON response
        set response_dict [json::json2dict $response]

        if {![dict exists $response_dict status] || [dict get $response_dict status] ne "ok"} {
            if {[dict exists $response_dict error]} {
                puts "ERROR: Engine startup failed: [dict get $response_dict error]"
            } else {
                puts "ERROR: Engine startup failed: $response"
            }
            return false
        }

        puts "Engine started successfully:"
        puts "  Engine: [dict get $response_dict engine]"
        puts "  Version: [dict get $response_dict version]"

        # Create recognizer command wrapper
        set recognizer_cmd [create_recognizer_cmd $engine_name]

        return true
    }

    # Cleanup
    proc cleanup {} {
        variable recognizer_cmd

        if {$recognizer_cmd ne ""} {
            catch {$recognizer_cmd close}
            set recognizer_cmd ""
        }
    }

    # Return the recognizer command (for audio.tcl)
    proc recognizer {} {
        variable recognizer_cmd
        return $recognizer_cmd
    }

    # Get current engine name
    proc current {} {
        variable engine_name
        return $engine_name
    }
}
