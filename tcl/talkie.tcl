#!/usr/bin/env tclsh
# talkie.tcl - Tcl version of Talkie

# Redefine bgerror to show errors on stderr instead of dialog
proc bgerror {message} {
    puts stderr "Background error: $message"
    puts stderr $::errorInfo
}

# Single instance enforcement
proc check_single_instance {} {
    set port 47823  ;# Unique port for talkie

    # Try to connect to existing instance
    if {![catch {socket localhost $port} sock]} {
        puts $sock "raise"
        flush $sock
        close $sock
        exit 0
    }

    # No existing instance - become the server
    socket -server handle_instance_request $port
}

proc handle_instance_request {sock addr port} {
    if {[gets $sock line] >= 0 && $line eq "raise"} {
        wm deiconify .
        raise .
        focus -force .
    }
    close $sock
}

check_single_instance

lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"

package require Tk
package require json
package require Ttk
package require jbr::unix
package require jbr::filewatch

tk appname Talkie
wm title . Talkie

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib pa]
lappend auto_path [file join $script_dir vosk lib vosk]
lappend auto_path [file join $script_dir audio lib audio]
lappend auto_path [file join $script_dir uinput lib uinput]

package require pa
package require vosk
package require audio
package require uinput

# Global state - using integer values to match ui-layout.tcl interface
set ::transcribing 0
set ::audiolevel 0
set ::confidence 0

proc quit {} {
    try { pa::terminate } on error message {}
    exit
}

source [file join $script_dir config.tcl]
source [file join $script_dir textproc.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir audio.tcl]
source [file join $script_dir threshold.tcl]
source [file join $script_dir ui-layout.tcl]

proc get_model_path {modelfile} {
    return [file join [file dirname $::script_dir] models vosk $modelfile]
}


set ::final_text_count 0

proc final_text {text confidence} {
    set final_text_lines [$::final cget -height]

    set timestamp [clock format [clock seconds] -format "%H:%M:%S"]

    if {$::final_text_count >= $final_text_lines } {
        $::final delete 1.0 2.0
    } else {
        incr ::final_text_count
    }

    $::final config -state normal
    $::final insert end "$timestamp " "timestamp"
    $::final insert end "([format "%.0f" $confidence]): $text\n"
    $::final see end
    $::final config -state disabled
}

proc partial_text {text} {
    $::partial config -state normal
    $::partial delete 1.0 end
    $::partial insert end $text
    $::partial config -state disabled
}

#
# Check uinput access after GUI is ready
#
proc check_uinput_access {} {
    if {![file exists /dev/uinput]} {
        puts "ERROR: /dev/uinput device not found"
        puts "       Run: sudo modprobe uinput"
        return false
    }

    if {![file writable /dev/uinput]} {
        set groups [exec groups]
        puts "ERROR: Cannot write to /dev/uinput"
        puts "       Current groups: $groups"
        puts "       Run: sudo usermod -a -G input $::env(USER)"
        puts "       Then logout and login again"
        return false
    }

    return true
}

proc check_and_display_uinput_status {} {
    if {![check_uinput_access]} {
        set error_msg "⚠️ KEYBOARD SIMULATION DISABLED\n\n"
        append error_msg "uinput device access failed. To fix:\n\n"
        append error_msg "1. Load uinput module:\n"
        append error_msg "   sudo modprobe uinput\n\n"
        append error_msg "2. Add user to input group:\n"
        append error_msg "   sudo usermod -a -G input $::env(USER)\n\n"
        append error_msg "3. Logout and login again\n\n"
        append error_msg "Current groups: [exec groups]\n"

        after idle [list $::final insert end $error_msg]
    }
}

config_init

puts "✓ Talkie Tcl Edition"

