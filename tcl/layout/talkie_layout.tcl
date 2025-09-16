#!/usr/bin/env tclsh
# talkie_layout.tcl - Layout-based version of Talkie

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

source [file join $script_dir config.tcl]
source [file join $script_dir vosk.tcl]
source [file join $script_dir audio.tcl]

source /home/john/src/jbr.tcl/layout/layout.tcl
source /home/john/src/jbr.tcl/layout/layout-option.tcl

source [file join $script_dir device_layout.tcl]
source [file join $script_dir display_layout.tcl]
source [file join $script_dir gui_layout.tcl]

# Initialize application
proc initialize_talkie {} {
    # Load configuration
    ::config::load

    # Initialize GUI (this will create the main window and layout)
    ::gui::initialize

    # Start UI updates
    ::display::start_ui_updates

    # Initialize audio stream for energy monitoring
    ::audio::initialize

    puts "✓ Talkie Tcl Edition (Layout-based)"
}

# Start the application
initialize_talkie
