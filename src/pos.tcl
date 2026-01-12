# POS-based homophone disambiguation wrapper
#
# Spawns pos_service.py as a coprocess for persistent disambiguation
# The Python service uses default paths from tools/ directory

namespace eval ::pos {
    variable enabled 1
    variable service_pid ""
    variable ready 0

    proc init {args} {
        variable service_pid
        variable ready

        puts stderr "POS: initializing service..."

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
        try {
            set cmd [list $python $py_script]
            set service_pid [open |$cmd r+]
            fconfigure $service_pid -buffering line -blocking 0

            # Wait for ready message
            puts stderr "POS: waiting for service startup..."
            after 5000  ;# Word bigrams take ~4s to load

            set ready 1
            puts stderr "POS: service ready"
        } on error {err} {
            puts stderr "POS: failed to start service: $err"
            set ready 0
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
