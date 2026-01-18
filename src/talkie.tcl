#!/usr/bin/env tclsh8.6
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
::tcl::tm::path add "$::env(HOME)/lib/tcl8/site-tcl"

package require Tk
package require json
package require Ttk
package require jbr::unix
package require jbr::filewatch

tk appname Talkie
wm title . Talkie
wm client . [info hostname]
wm command . [list [info nameofexecutable] {*}$::argv0 {*}$::argv]
wm protocol . WM_DELETE_WINDOW quit

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib pa]
lappend auto_path [file join $script_dir audio lib audio]
lappend auto_path [file join $script_dir uinput lib uinput]

package require pa
package require audio
package require uinput

# Global state - using integer values to match ui-layout.tcl interface
set ::transcribing 0
set ::audiolevel 0
set ::confidence 0
set ::buffer_health 0
set ::buffer_overflows 0

proc quit {} {
    try { ::gec_worker::cleanup } on error message {}
    try { ::output::cleanup } on error message {}
    try { ::engine::cleanup } on error message {}
    try { pa::terminate } on error message {}
    exit
}

# Load config first to know which engine to use
source [file join $script_dir config.tcl]
source [file join $script_dir textproc.tcl]
source [file join $script_dir threshold.tcl]
source [file join $script_dir ui-layout.tcl]

# Early load to get speech_engine setting
config_load

# Load the configured speech engine dynamically
if {![info exists ::config(speech_engine)]} {
    set ::config(speech_engine) "vosk"
}

# Load critcl engines at startup (only Vosk now)
# Vosk - in-process critcl bindings
lappend auto_path [file join $script_dir vosk lib vosk]
package require vosk
source [file join $script_dir vosk.tcl]

# All other engines (Sherpa, Faster-Whisper) are coprocess - no loading needed

# Feedback logging (must load before gec.tcl and output.tcl)
source [file join $script_dir feedback.tcl]
::feedback::init

# Load engine abstraction layer
source [file join $script_dir engine.tcl]
source [file join $script_dir output.tcl]
source [file join $script_dir audio.tcl]
source [file join $script_dir gec_worker.tcl]

# Model paths - see CLAUDE.md "Vosk Model Data" section
set models_dir [file join [file dirname $::script_dir] models vosk]
set base_model_dir [file join $models_dir vosk-model-en-us-0.22-lgraph]  ;# Base model (reference)
set custom_model_dir [file join $models_dir lm-test]                     ;# Custom model with domain words

proc get_model_path {modelfile} {
    # Generic model path lookup - delegates to engine.tcl
    # This is kept for backward compatibility with vosk.tcl and sherpa.tcl
    # New coprocess engines use engine::get_property directly

    set model_dir [::engine::get_property $::config(speech_engine) model_dir]
    if {$model_dir eq ""} {
        return ""
    }

    return [file join [file dirname $::script_dir] models $model_dir $modelfile]
}


set ::final_text_count 0

proc final_text {text confidence {vosk_ms 0} {gec_timing {}}} {
    set final_text_lines [$::final cget -height]

    set timestamp [clock format [clock seconds] -format "%H:%M:%S"]

    if {$::final_text_count >= $final_text_lines } {
        $::final delete 1.0 2.0
    } else {
        incr ::final_text_count
    }

    # Build timing string: V=vosk H=homophone P=punctcap (all in ms)
    set timing_str ""
    if {$vosk_ms > 0 || [dict size $gec_timing] > 0} {
        set parts {}
        if {$vosk_ms > 0} {
            lappend parts "V:[format %.0f $vosk_ms]"
        }
        if {[dict exists $gec_timing homo_ms]} {
            lappend parts "H:[format %.0f [dict get $gec_timing homo_ms]]"
        }
        if {[dict exists $gec_timing punct_ms]} {
            lappend parts "P:[format %.0f [dict get $gec_timing punct_ms]]"
        }
        if {[llength $parts] > 0} {
            set timing_str " \[[join $parts " "]\]"
        }
    }

    $::final config -state normal
    $::final insert end "$timestamp " "timestamp"
    $::final insert end "([format "%.0f" $confidence])$timing_str: $text\n"
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
        puts ""
        puts "       Fix for Void Linux:"
        puts "         sudo chgrp input /dev/uinput"
        puts "         sudo chmod 660 /dev/uinput"
        puts "       Or install the uinput-perms runit service."
        puts ""
        puts "       If not in input group:"
        puts "         sudo usermod -a -G input $::env(USER)"
        puts "         Then logout and login again"
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
        append error_msg "2. Set device permissions (Void Linux):\n"
        append error_msg "   sudo chgrp input /dev/uinput\n"
        append error_msg "   sudo chmod 660 /dev/uinput\n"
        append error_msg "   Or install the uinput-perms runit service.\n\n"
        append error_msg "3. Add user to input group (if needed):\n"
        append error_msg "   sudo usermod -a -G input $::env(USER)\n"
        append error_msg "   Then logout and login again\n\n"
        append error_msg "Current groups: [exec groups]\n"

        after idle [list $::final insert end $error_msg]
    }
}

after idle {
    after 100 {
        set frame [wm frame .]
        if {$frame ne "0x0"} {
            exec xprop -id $frame -f _NET_WM_PID 32c -set _NET_WM_PID [pid]
        }
    }
}

config_init

puts "✓ Talkie Tcl Edition"

