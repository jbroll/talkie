#!/usr/bin/env tclsh
# talkie.tcl - Tcl version of Talkie

package require Tk
package require json
package require Ttk

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib pa]
lappend auto_path [file join $script_dir vosk lib vosk]
lappend auto_path [file join $script_dir audio lib audio]
set ::env(TCLLIBPATH) "$::env(HOME)/.local/lib"

package require pa
package require vosk
package require audio

# Source all modules
source [file join $script_dir config.tcl]
source [file join $script_dir device.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir display.tcl]
source [file join $script_dir audio.tcl]
source [file join $script_dir gui.tcl]

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
    variable current_confidence

    if { $result eq "" } { return }

    set result_dict [json::json2dict $result]

    if {[dict exists $result_dict partial]} {
        set text [dict get $result_dict partial]
        after idle [list ::display::update_partial_text $text]
        return
    }

    set text [json-get $result_dict alternatives 0 text]
    set conf [json-get $result_dict alternatives 0 confidence]

    if {$text ne ""} {
        set confidence_threshold [::config::get confidence_threshold]
        if {$confidence_threshold == 0 || $conf >= $confidence_threshold} {
            after idle [list ::display::display_final_text $text $conf]
        } else {
            puts "VOSK-FILTERED: text='$text' confidence=$conf below threshold $confidence_threshold"
        }
        set current_confidence $conf
    }
}


::config::load
::gui::initialize
::device::refresh_devices
::display::start_ui_updates
::audio::initialize

puts "✓ Talkie Tcl Edition"

after idle {
    ::gui::show_default_view
}

