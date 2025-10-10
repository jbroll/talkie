# Mock PortAudio module
package provide pa 1.0

namespace eval ::pa {
    variable mock_devices {}
    variable mock_stream_callback ""
    variable mock_stream_active 0
}

# Mock device list
proc ::pa::list_devices {} {
    return {
        {name "Mock Device 1" maxInputChannels 1}
        {name "Mock Device 2" maxInputChannels 2}
        {name "pulse" maxInputChannels 1}
    }
}

# Mock stream creation
proc ::pa::open_stream {args} {
    variable mock_stream_callback

    # Parse arguments
    array set params $args
    if {[info exists params(-callback)]} {
        set mock_stream_callback $params(-callback)
    }

    return "mock_stream"
}

# Mock stream object methods
proc mock_stream {method args} {
    variable ::pa::mock_stream_active
    variable ::pa::mock_stream_callback

    switch $method {
        "start" {
            set mock_stream_active 1
            return
        }
        "stop" {
            set mock_stream_active 0
            return
        }
        "simulate_audio" {
            # Simulate audio callback with test data
            set timestamp [clock milliseconds]
            set data [lindex $args 0]
            if {$mock_stream_callback ne "" && $mock_stream_active} {
                $mock_stream_callback "mock_stream" $timestamp $data
            }
        }
    }
}

proc ::pa::terminate {} {
    # Mock cleanup
}

# The mock_stream proc is already defined above, no alias needed