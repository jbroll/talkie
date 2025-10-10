# engine.tcl - Speech engine abstraction layer
# Provides a unified interface regardless of which engine is loaded

namespace eval ::engine {
    variable recognizer ""
    variable model ""
    variable current_engine ""

    # Initialize the configured speech engine
    proc initialize {} {
        variable recognizer
        variable current_engine

        set current_engine $::config(speech_engine)

        if {$current_engine eq "vosk"} {
            if {[::vosk::initialize]} {
                set recognizer $::vosk_recognizer
                return true
            }
            return false
        } elseif {$current_engine eq "sherpa"} {
            if {[::sherpa::initialize]} {
                set recognizer $::sherpa_recognizer
                return true
            }
            return false
        } else {
            puts "Unknown speech engine: $current_engine"
            return false
        }
    }

    # Cleanup current engine
    proc cleanup {} {
        variable recognizer
        variable current_engine

        if {$current_engine eq "vosk"} {
            ::vosk::cleanup
        } elseif {$current_engine eq "sherpa"} {
            ::sherpa::cleanup
        }

        set recognizer ""
    }

    # Get the recognizer command (abstraction)
    proc recognizer {} {
        variable recognizer
        return $recognizer
    }

    # Get current engine name
    proc current {} {
        variable current_engine
        return $current_engine
    }
}
