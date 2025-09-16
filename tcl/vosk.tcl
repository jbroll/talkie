# vosk.tcl - Vosk speech recognition for Talkie
package require json

namespace eval ::vosk {
    variable model ""
    variable recognizer ""
    variable current_confidence 0.0

    proc json-get {container args} {
        set current $container
        foreach step $args {
            if {[string is integer -strict $step]} {
                set current [lindex $current $step]
            } else {
                set current [dict get $current $step]
            }
        }
        return $current
    }

    proc parse_and_display_result {result} {
        variable current_confidence

        try {
            set result_dict [json::json2dict $result]

            if {[dict exists $result_dict partial]} {
                set text [dict get $result_dict partial]
                after idle [list ::display::update_partial_text $text]
                return
            }

            set text [json-get $result_dict alternatives 0 text]
            set conf [json-get $result_dict alternatives 0 confidence]

            if {$text ne ""} {
                set confidence_threshold [::config::get confidence_threshold]
                if {$confidence_threshold == 0 || $conf >= $confidence_threshold} {
                    after idle [list ::display::display_final_text $text $conf]
                } else {
                    puts "VOSK-FILTERED: text='$text' confidence=$conf below threshold $confidence_threshold"
                }
                set current_confidence $conf
            }
        } on error message {
            puts "VOSK-PARSE-ERROR: $message"
        }
    }

    proc initialize {} {
        variable model
        variable recognizer

        if {[catch {
            if {[info commands vosk::set_log_level] ne ""} {
                vosk::set_log_level -1
            }

            set model_path [::config::get model_path]
            if {[file exists $model_path]} {
                set model [vosk::load_model -path $model_path]
                set recognizer [$model create_recognizer -rate [::config::get sample_rate]]
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