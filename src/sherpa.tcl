set ::sherpa_recognizer ""

namespace eval ::sherpa {
    variable model ""
    variable wrapper_count 0

    proc initialize {} {
        variable model

        if {[catch {
            set model_path [get_model_path $::config(sherpa_modelfile)]
            if {$model_path ne "" && [file exists $model_path]} {
                set model [sherpa::load_model -path $model_path]
                set real_recognizer [$model create_recognizer -rate $::device_sample_rate \
                    -max_active_paths $::config(sherpa_max_active_paths)]

                # Wrap the recognizer to convert results to Vosk format
                set ::sherpa_recognizer [create_vosk_compatible_recognizer $real_recognizer]
                puts "✓ Sherpa-ONNX model loaded: $model_path"
            } else {
                puts "Sherpa model not found: $::config(sherpa_modelfile)"
                return false
            }
        } sherpa_err]} {
            puts "Sherpa initialization error: $sherpa_err"
            return false
        }

        return true
    }

    # Create a recognizer wrapper that returns Vosk-compatible results
    proc create_vosk_compatible_recognizer {real_recognizer} {
        set wrapper_name "::sherpa::wrapped_recognizer_[incr ::sherpa::wrapper_count]"
        set ::sherpa::real_recognizer($wrapper_name) $real_recognizer

        proc $wrapper_name {subcommand args} {
            set real_rec $::sherpa::real_recognizer([lindex [info level 0] 0])
            puts "SHERPA CALL: $subcommand"
            set result [$real_rec $subcommand {*}$args]

            # Convert result to Vosk format for process and final-result
            if {$subcommand eq "process" || $subcommand eq "final-result"} {
                return [::sherpa::to_vosk_format $result $subcommand]
            }

            return $result
        }

        return $wrapper_name
    }

    proc cleanup {} {
        variable model

        # Destroy recognizer command if it exists
        if {$::sherpa_recognizer ne "" && [info commands $::sherpa_recognizer] ne ""} {
            # Clean up the real recognizer reference
            if {[info exists ::sherpa::real_recognizer($::sherpa_recognizer)]} {
                catch {rename $::sherpa::real_recognizer($::sherpa_recognizer) ""}
                unset ::sherpa::real_recognizer($::sherpa_recognizer)
            }
            catch {rename $::sherpa_recognizer ""}
        }
        set ::sherpa_recognizer ""

        # Clear model reference (Tcl will handle cleanup)
        set model ""

        puts "Sherpa-ONNX engine cleaned up"
    }

    # Convert Sherpa-ONNX result to Vosk-compatible format
    # Vosk format: {"partial": "..."} or {"alternatives": [{"text": "...", "confidence": 0.95}]}
    proc to_vosk_format {sherpa_json subcommand} {
        puts "SHERPA RAW ($subcommand): $sherpa_json"

        if {$sherpa_json eq "" || $sherpa_json eq "{}"} {
            return {{"alternatives": [{"text": "", "confidence": 0.0}]}}
        }

        set result_dict [json::json2dict $sherpa_json]

        # Get text and convert to lowercase (Sherpa returns uppercase)
        set text ""
        if {[dict exists $result_dict text]} {
            set text [string tolower [dict get $result_dict text]]
        }

        # Convert Sherpa's ys_probs to Vosk-compatible confidence
        # Sherpa provides negative log probabilities, Vosk uses 0-400+ scale
        set confidence 100.0
        if {[dict exists $result_dict ys_probs]} {
            set ys_probs [dict get $result_dict ys_probs]
            if {[llength $ys_probs] > 0} {
                # Average the negative log probs
                set sum 0.0
                foreach prob $ys_probs {
                    set sum [expr {$sum + $prob}]
                }
                set avg [expr {$sum / [llength $ys_probs]}]

                # Convert to Vosk-like scale: multiply by -400
                # -0.25 → 100, -0.5 → 200, -1.0 → 400, etc.
                set confidence [expr {-400.0 * $avg}]
            }
        }

        puts "SHERPA PARSED: text='$text' confidence=$confidence method=$subcommand"

        # Determine if this is final based on the method called
        # final-result method = final, process method = partial
        if {$subcommand eq "final-result"} {
            # Return final format with Vosk-style alternatives array
            # Build JSON manually to ensure proper array format
            set json_result "{\"alternatives\": \[\{\"text\": \"$text\", \"confidence\": $confidence\}\]}"
            puts "SHERPA → FINAL: $json_result"
            return $json_result
        } else {
            # Return partial format for process calls
            if {$text ne ""} {
                set result [json::dict2json [dict create partial $text]]
                puts "SHERPA → PARTIAL: $result"
                return $result
            } else {
                # Empty text, return empty final format
                return {{"alternatives": [{"text": "", "confidence": 0.0}]}}
            }
        }
    }
}
