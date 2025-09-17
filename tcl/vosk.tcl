# vosk.tcl - Vosk speech recognition for Talkie
package require json

# Global recognizer - created once at startup
set ::vosk_recognizer ""

namespace eval ::vosk {
    variable model ""
    variable current_confidence 0.0

    proc initialize {} {
        variable model

        if {[catch {
            if {[info commands vosk::set_log_level] ne ""} {
                vosk::set_log_level -1
            }

            set model_path $::config::config(model_path)
            if {[file exists $model_path]} {
                set model [vosk::load_model -path $model_path]
                set ::vosk_recognizer [$model create_recognizer -rate $::config::config(sample_rate)]
            } else {
                puts "Vosk model not found at $model_path"
                return false
            }
        } vosk_err]} {
            puts "Vosk initialization error: $vosk_err"
            return false
        }

        return true
    }

    proc cleanup {} {
        variable model

        set ::vosk_recognizer ""
        set model ""
    }


    proc get_confidence {} {
        variable current_confidence
        return $current_confidence
    }

    proc reset_recognizer {} {
        # Reset recognizer state for clean transcription start
        $::vosk_recognizer reset
    }
}
