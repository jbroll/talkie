#!/usr/bin/env tclsh
# talkie.tcl - Tcl version of Talkie

# Redefine bgerror to show errors on stderr instead of dialog
proc bgerror {message} {
    puts stderr "Background error: $message"
    puts stderr $::errorInfo
}

lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"

package require Tk
package require json
package require Ttk
package require jbr::unix
package require jbr::filewatch

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

# Trace callback for transcription state changes
proc handle_transcribing_change {args} {
    if {$::transcribing} {
        ::audio::start_transcription
    } else {
        ::audio::stop_transcription
    }
}

proc quit {} {
    try { pa::terminate } on error message {}
    exit
}

source [file join $script_dir config.tcl]
source [file join $script_dir device.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir display.tcl]
source [file join $script_dir audio.tcl]
source [file join $script_dir ui-layout.tcl]

proc refresh_models {} {
    set models_dir [file join [file dirname $::script_dir] models vosk]
    set ::model_files [lsort [lmap item [glob -nocomplain -directory $models_dir -type d *] {file tail $item}]]
}

proc get_model_path {modelfile} {
    return [file join [file dirname $::script_dir] models vosk $modelfile]
}

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
    if { $result eq "" } { return }

    set result_dict [json::json2dict $result]

    if {[dict exists $result_dict partial]} {
        set text [dict get $result_dict partial]

        after idle [list $::partial delete 1.0 end]
        after idle [list $::partial insert end $text]
        return
    }

    set text [json-get $result_dict alternatives 0 text]
    set conf [json-get $result_dict alternatives 0 confidence]

    if {$text ne ""} {
        set confidence_threshold $::config(confidence_threshold)
        if {$confidence_threshold == 0 || $conf >= $confidence_threshold} {
            uinput::type $text
            after idle [list $::final insert end "$text\n"]
        } else {
            puts "VOSK-FILTERED: text='$text' confidence=$conf below threshold $confidence_threshold"
        }
        set ::confidence $conf
    }
}


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

::config::load
set ::transcribing [::config::load_state]
trace add variable ::transcribing write handle_transcribing_change
::config::setup_trace
::config::setup_file_watcher
::device::refresh_devices
::audio::initialize

refresh_models

puts "✓ Talkie Tcl Edition"

