# coprocess.tcl - Simple speech engine IPC manager
# Protocol: Text commands in, JSON responses out

namespace eval ::coprocess {
    variable engines {}  ;# dict: name -> channel

    # Start engine with model path and sample rate
    proc start {name command model_path sample_rate} {
        variable engines

        # Convert sample rate to integer (no decimals)
        set sample_rate_int [expr {int($sample_rate)}]

        # Launch with model path as argument (use list to avoid command injection)
        set chan [open |[list $command $model_path $sample_rate_int] r+]
        fconfigure $chan -buffering line -encoding utf-8

        # Read startup response (JSON)
        set response [gets $chan]
        if {$response eq ""} {
            close $chan
            error "Engine startup failed: no response"
        }

        dict set engines $name $chan
        return $response
    }

    # Send binary command: PROCESS byte_count + binary data
    proc send_binary {name command byte_count data} {
        variable engines
        set chan [dict get $engines $name]

        # Send command with byte count
        puts $chan "$command $byte_count"
        flush $chan

        # Switch to binary mode for data
        fconfigure $chan -buffering full -translation binary
        puts -nonewline $chan $data
        flush $chan

        # Switch back to line mode for response
        fconfigure $chan -buffering line -encoding utf-8 -translation auto
    }

    # Receive JSON response
    proc receive {name} {
        variable engines
        set chan [dict get $engines $name]
        return [gets $chan]
    }

    # High-level commands

    # Process audio chunk - returns JSON
    proc process {name audio_data} {
        set byte_count [string length $audio_data]
        send_binary $name PROCESS $byte_count $audio_data
        return [receive $name]
    }

    # Get final result - returns JSON
    proc final {name} {
        variable engines
        set chan [dict get $engines $name]
        puts $chan "FINAL"
        flush $chan
        return [receive $name]
    }

    # Reset recognizer - returns JSON
    proc reset {name} {
        variable engines
        set chan [dict get $engines $name]
        puts $chan "RESET"
        flush $chan
        return [receive $name]
    }

    # Change model - returns JSON
    proc model {name model_path} {
        variable engines
        set chan [dict get $engines $name]
        puts $chan "MODEL $model_path"
        flush $chan
        return [receive $name]
    }

    # Stop engine
    proc stop {name} {
        variable engines
        if {![dict exists $engines $name]} {
            return
        }

        set chan [dict get $engines $name]
        catch {close $chan}
        dict unset engines $name
    }
}
