# Mock Vosk module
package provide vosk 1.0

namespace eval ::vosk {
    variable mock_recognizer ""
    variable mock_results {}
    variable mock_result_index 0
}

proc ::vosk::initialize {} {
    variable mock_recognizer
    set mock_recognizer "mock_vosk_recognizer"
    set ::vosk_recognizer $mock_recognizer
    return true
}

# Mock recognizer object methods
proc mock_vosk_recognizer {method args} {
    variable ::vosk::mock_results
    variable ::vosk::mock_result_index

    switch $method {
        "process" {
            # Return next mock result or partial
            if {$mock_result_index < [llength $mock_results]} {
                set result [lindex $mock_results $mock_result_index]
                incr mock_result_index
                return $result
            }
            return {{"partial": ""}}
        }
        "final-result" {
            # Return final result
            return {{"alternatives": [{"text": "mock final result", "confidence": 0.85}]}}
        }
        "reset" {
            set mock_result_index 0
            return
        }
    }
}

# Test utility to set mock results
proc ::vosk::set_mock_results {results} {
    variable mock_results
    variable mock_result_index
    set mock_results $results
    set mock_result_index 0
}

# The mock_vosk_recognizer proc is already defined above, no alias needed