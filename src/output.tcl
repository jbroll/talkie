# output.tcl - Dedicated output thread for keyboard simulation
# Decouples uinput typing from audio callback and main thread

source [file join [file dirname [info script]] worker.tcl]

namespace eval ::output {
    variable worker_name "output"

    # Worker thread script (sent to worker thread)
    variable worker_script {
        package require Thread

        namespace eval ::output::worker {
            variable initialized 0
            variable main_tid ""
            variable script_dir ""

            proc init {main_tid_arg script_dir_arg typing_delay} {
                variable main_tid $main_tid_arg
                variable script_dir $script_dir_arg
                variable initialized

                # Set up auto_path for uinput package
                lappend ::auto_path [file join $script_dir uinput lib uinput]

                # Load uinput package
                if {[catch {package require uinput} err]} {
                    return [list status error message "Failed to load uinput: $err"]
                }

                # Set typing delay
                if {[catch {uinput::set_typing_delay $typing_delay} err]} {
                    return [list status error message "Failed to set typing delay: $err"]
                }

                set initialized 1
                return [list status ok message "Output worker initialized"]
            }

            proc type_text {text} {
                variable initialized

                if {!$initialized} {
                    puts stderr "Output worker: not initialized, skipping text: $text"
                    return
                }

                try {
                    uinput::type $text
                } on error {err info} {
                    puts stderr "Output worker: typing error: $err"
                }
            }

            proc set_delay {delay_ms} {
                variable initialized

                if {!$initialized} {
                    return
                }

                try {
                    uinput::set_typing_delay $delay_ms
                } on error {err info} {
                    puts stderr "Output worker: set_delay error: $err"
                }
            }

            proc close {} {
                variable initialized

                if {!$initialized} {
                    return
                }

                try {
                    uinput::cleanup
                    set initialized 0
                } on error {err info} {
                    puts stderr "Output worker: cleanup error: $err"
                }
            }
        }
    }

    # Initialize output thread
    proc initialize {} {
        variable worker_name
        variable worker_script

        set main_tid [thread::id]

        puts "Initializing output thread for keyboard simulation..."

        # Create worker thread using worker module
        set worker_tid [::worker::create $worker_name $worker_script]

        puts "  Worker thread: $worker_tid"
        puts "  Main thread: $main_tid"

        # Get typing delay from config (default 10ms)
        set typing_delay 10
        if {[info exists ::config(typing_delay_ms)]} {
            set typing_delay $::config(typing_delay_ms)
        }

        # Initialize worker thread
        set response [::worker::send $worker_name [list ::output::worker::init \
            $main_tid $::script_dir $typing_delay]]

        # Check response
        if {[dict get $response status] ne "ok"} {
            puts "ERROR: Output worker initialization failed: [dict get $response message]"
            ::worker::destroy $worker_name
            return false
        }

        puts "✓ Output worker thread initialized successfully"
        puts "  [dict get $response message]"
        puts "  Typing delay: ${typing_delay}ms"

        return true
    }

    # Asynchronously send text to output thread for typing
    proc type_async {text} {
        variable worker_name

        # Skip empty text
        if {$text eq ""} {
            return
        }

        # Log injection for feedback learning
        ::feedback::inject $text

        # Check if worker thread exists
        if {![::worker::exists $worker_name]} {
            puts stderr "Output thread not available, text dropped: $text"
            return
        }

        # Send text to worker thread (non-blocking)
        ::worker::send_async $worker_name [list ::output::worker::type_text $text]
    }

    # Update typing delay (synchronous, should be rare)
    proc set_typing_delay {delay_ms} {
        variable worker_name

        if {![::worker::exists $worker_name]} {
            return
        }

        ::worker::send $worker_name [list ::output::worker::set_delay $delay_ms]
    }

    # Cleanup output thread
    proc cleanup {} {
        variable worker_name

        if {![::worker::exists $worker_name]} {
            return
        }

        puts "Cleaning up output thread..."

        # Close worker
        ::worker::send $worker_name {::output::worker::close}

        # Destroy worker
        ::worker::destroy $worker_name

        puts "Output thread cleanup complete"
    }
}
