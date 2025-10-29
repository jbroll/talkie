# output.tcl - Dedicated output thread for keyboard simulation
# Decouples uinput typing from audio callback and main thread

package require Thread

namespace eval ::output {
    variable worker_tid ""
    variable main_tid ""

    # Worker thread procedures (executed in worker thread context)
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

    # Initialize output thread
    proc initialize {} {
        variable worker_tid
        variable main_tid

        # Save main thread ID
        set main_tid [thread::id]

        puts "Initializing output thread for keyboard simulation..."

        # Create worker thread
        set worker_tid [thread::create {
            namespace eval ::output::worker {}
            thread::wait
        }]

        # Send the worker procedures to the worker thread
        thread::send $worker_tid [list namespace eval ::output::worker {
            variable initialized 0
            variable main_tid ""
            variable script_dir ""

            proc init {main_tid_arg script_dir_arg typing_delay} {
                variable main_tid $main_tid_arg
                variable script_dir $script_dir_arg
                variable initialized

                package require Thread

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
        }]

        puts "  Worker thread: $worker_tid"
        puts "  Main thread: $main_tid"

        # Get typing delay from config (default 10ms)
        set typing_delay 10
        if {[info exists ::config(typing_delay_ms)]} {
            set typing_delay $::config(typing_delay_ms)
        }

        # Initialize worker thread
        set response [thread::send $worker_tid [list ::output::worker::init \
            $main_tid $::script_dir $typing_delay]]

        # Check response
        if {[dict get $response status] ne "ok"} {
            puts "ERROR: Output worker initialization failed: [dict get $response message]"
            catch {thread::release $worker_tid}
            set worker_tid ""
            return false
        }

        puts "✓ Output worker thread initialized successfully"
        puts "  [dict get $response message]"
        puts "  Typing delay: ${typing_delay}ms"

        return true
    }

    # Asynchronously send text to output thread for typing
    proc type_async {text} {
        variable worker_tid

        # Skip empty text
        if {$text eq ""} {
            return
        }

        # Check if worker thread exists
        if {$worker_tid eq "" || ![catch {thread::exists $worker_tid} exists] && !$exists} {
            puts stderr "Output thread not available, text dropped: $text"
            return
        }

        # Send text to worker thread (non-blocking)
        catch {thread::send -async $worker_tid [list ::output::worker::type_text $text]}
    }

    # Update typing delay (synchronous, should be rare)
    proc set_typing_delay {delay_ms} {
        variable worker_tid

        if {$worker_tid eq "" || ![catch {thread::exists $worker_tid} exists] && !$exists} {
            return
        }

        catch {thread::send $worker_tid [list ::output::worker::set_delay $delay_ms]}
    }

    # Cleanup output thread
    proc cleanup {} {
        variable worker_tid

        if {$worker_tid eq ""} {
            return
        }

        puts "Cleaning up output thread..."

        # Close worker
        catch {thread::send $worker_tid {::output::worker::close}}

        # Release thread
        catch {thread::release $worker_tid}
        set worker_tid ""

        puts "Output thread cleanup complete"
    }
}
