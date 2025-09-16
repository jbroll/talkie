# vosk.tcl - Vosk speech recognition for Talkie
package require json

namespace eval ::vosk {
    variable model ""
    variable recognizer ""
    variable current_confidence 0.0

    proc initialize {} {
        variable model
        variable recognizer

        if {[catch {
            if {[info commands vosk::set_log_level] ne ""} {
                vosk::set_log_level -1
            }

            set model_path $::config::config(model_path)
            if {[file exists $model_path]} {
                set model [vosk::load_model -path $model_path]
                set recognizer [$model create_recognizer -rate $::config::config(sample_rate)]
                return true
            } else {
                puts "Vosk model not found at $model_path"
                return false
            }
        } vosk_err]} {
            puts "Vosk initialization error: $vosk_err"
            return false
        }
    }

    proc cleanup {} {
        variable model
        variable recognizer

        set recognizer ""
        set model ""
    }

    proc get_recognizer {} {
        variable recognizer
        return $recognizer
    }

    proc get_confidence {} {
        variable current_confidence
        return $current_confidence
    }
}
