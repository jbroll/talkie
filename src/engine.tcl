# engine.tcl - Hybrid speech engine abstraction layer
# Supports both in-process (critcl) and coprocess engines

source coprocess.tcl

namespace eval ::engine {
    variable recognizer_cmd ""
    variable engine_name ""

    # Engine registry - central configuration
    variable engine_registry
    array set engine_registry {
        vosk,command      ""
        vosk,type         "critcl"
        vosk,model_dir    "vosk"
        vosk,model_config "vosk_modelfile"

        sherpa,command      "engines/sherpa_wrapper.sh"
        sherpa,type         "coprocess"
        sherpa,model_dir    "sherpa-onnx"
        sherpa,model_config "sherpa_modelfile"

        faster-whisper,command      "engines/faster_whisper_wrapper.sh"
        faster-whisper,type         "coprocess"
        faster-whisper,model_dir    "faster-whisper"
        faster-whisper,model_config "faster_whisper_modelfile"
    }

    # Check if engine is registered
    proc is_registered {engine_name} {
        variable engine_registry
        return [info exists engine_registry($engine_name,type)]
    }

    # Get engine property
    proc get_property {engine_name property} {
        variable engine_registry
        set key "${engine_name},${property}"
        if {[info exists engine_registry($key)]} {
            return $engine_registry($key)
        }
        return ""
    }

    # Create a recognizer command wrapper for coprocess engines
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

        # Check if engine is registered
        if {![is_registered $engine_name]} {
            puts "ERROR: Unknown engine: $engine_name"
            return false
        }

        set engine_type [get_property $engine_name type]

        # Branch based on engine type
        if {$engine_type eq "critcl"} {
            # In-process engine (Vosk only)
            # Package loaded at startup
            puts "Using in-process $engine_name engine (critcl bindings)"

            if {$engine_name eq "vosk"} {
                if {[::vosk::initialize]} {
                    set recognizer_cmd $::vosk_recognizer
                    return true
                }
                return false
            } else {
                puts "ERROR: Unknown critcl engine: $engine_name"
                return false
            }

        } elseif {$engine_type eq "coprocess"} {
            # New coprocess engine (faster-whisper, etc.)
            set cmd [get_property $engine_name command]

            # Get model path - generic lookup
            set model_config [get_property $engine_name model_config]
            set model_dir [get_property $engine_name model_dir]

            if {$model_config ne "" && [info exists ::config($model_config)]} {
                set modelfile $::config($model_config)
                set model_path [file join [file dirname $::script_dir] models $model_dir $modelfile]
            } else {
                # No model config - just use model directory
                set model_path [file join [file dirname $::script_dir] models $model_dir]
            }

            puts "Starting $engine_name coprocess engine..."
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
            if {[dict exists $response_dict version]} {
                puts "  Version: [dict get $response_dict version]"
            }

            # Create recognizer command wrapper
            set recognizer_cmd [create_recognizer_cmd $engine_name]

            return true

        } else {
            puts "ERROR: Unknown engine type: $engine_type"
            return false
        }
    }

    # Cleanup
    proc cleanup {} {
        variable recognizer_cmd
        variable engine_name

        # Safety check - if engine_name is empty, nothing to cleanup
        if {$engine_name eq ""} {
            return
        }

        set engine_type [get_property $engine_name type]

        puts "Cleaning up $engine_name engine (type: $engine_type)..."

        if {$engine_type eq "critcl"} {
            # In-process cleanup (Vosk only)
            if {$engine_name eq "vosk"} {
                ::vosk::cleanup
            }
        } elseif {$engine_type eq "coprocess"} {
            # Coprocess cleanup
            if {$recognizer_cmd ne ""} {
                catch {$recognizer_cmd close}
                set recognizer_cmd ""
            }
            # Ensure coprocess is stopped
            catch {::coprocess::stop $engine_name}
        }

        set recognizer_cmd ""
        puts "Cleanup complete"
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
