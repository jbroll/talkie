set ::vosk_recognizer ""

namespace eval ::vosk {
    variable model ""

    proc initialize {} {
        variable model

        if {[catch {
            if {[info commands vosk::set_log_level] ne ""} {
                vosk::set_log_level -1
            }

            set model_path [get_model_path $::config(vosk_modelfile)]
            if {$model_path ne "" && [file exists $model_path]} {
                set model [vosk::load_model -path $model_path]
                set ::vosk_recognizer [$model create_recognizer -rate $::device_sample_rate]
                puts "✓ Vosk model loaded: $model_path"
            } else {
                puts "ERROR: Vosk model not found: $model_path"
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

        # Destroy recognizer command if it exists
        if {$::vosk_recognizer ne "" && [info commands $::vosk_recognizer] ne ""} {
            catch {rename $::vosk_recognizer ""}
        }
        set ::vosk_recognizer ""

        # Clear model reference (Tcl will handle cleanup)
        set model ""

        puts "Vosk engine cleaned up"
    }
}
