# POS-based homophone disambiguation wrapper
#
# Spawns pos_service.py as a coprocess for persistent disambiguation
# The Python service uses default paths from tools/ directory
# Startup is async to overlap with audio calibration

namespace eval ::pos {
    variable enabled 1
    variable service_pid ""
    variable ready 0

    proc init {args} {
        variable service_pid
        variable ready

        puts stderr "POS: initializing service (async)..."

        # Find the service script
        set script_dir [file dirname [info script]]
        set py_script [file join $script_dir pos_service.py]

        if {![file exists $py_script]} {
            puts stderr "POS: service script not found: $py_script"
            return
        }

        # Check for venv python
        set venv_python [file join [file dirname $script_dir] venv bin python3]
        if {[file exists $venv_python]} {
            set python $venv_python
        } else {
            set python python3
        }

        # Spawn the service as a coprocess (uses defaults from tools/)
        # Use -u for unbuffered stderr
        try {
            set cmd [list $python -u $py_script]
            set service_pid [open |$cmd r+]
            fconfigure $service_pid -buffering line -blocking 0

            # Set up fileevent to read the READY message from stdout
            fileevent $service_pid readable [namespace code [list read_startup $service_pid]]

            # Schedule ready check - don't block startup
            # Word bigrams take ~4s to load, check after 5s
            after 5000 [namespace code check_ready]
        } on error {err} {
            puts stderr "POS: failed to start service: $err"
            set ready 0
        }
    }

    proc read_startup {fd} {
        variable ready

        if {[eof $fd]} {
            fileevent $fd readable {}
            return
        }

        if {[gets $fd line] >= 0} {
            # Display startup messages
            if {[string match "POS:*" $line] || [string match "POS_READY*" $line]} {
                puts stderr $line
            }
            # Mark ready when we see POS_READY
            if {[string match "POS_READY*" $line]} {
                set ready 1
                # Stop reading startup messages, switch to normal mode
                fileevent $fd readable {}
            }
        }
    }

    proc check_ready {} {
        variable service_pid
        variable ready

        if {$service_pid eq ""} {
            return
        }

        # Fallback if POS_READY wasn't seen - mark ready anyway
        if {!$ready} {
            set ready 1
            puts stderr "POS: service ready (timeout fallback)"
        }
    }

    proc shutdown {} {
        variable service_pid
        variable ready

        if {$service_pid ne ""} {
            catch {close $service_pid}
            set service_pid ""
        }
        set ready 0
    }

    proc disambiguate {text} {
        variable enabled
        variable service_pid
        variable ready

        if {!$enabled || !$ready || $text eq ""} {
            return $text
        }

        try {
            # Send text to service
            puts $service_pid $text
            flush $service_pid

            # Read result (with timeout)
            set result ""
            set timeout 0
            while {$result eq "" && $timeout < 100} {
                set result [gets $service_pid]
                if {$result eq ""} {
                    after 10
                    incr timeout
                }
            }

            if {$result eq ""} {
                puts stderr "POS: timeout waiting for response"
                return $text
            }

            return $result
        } on error {err} {
            puts stderr "POS error: $err"
            return $text
        }
    }
}
