#!/usr/bin/env tclsh
# talkie_modular.tcl - Modular version of Talkie

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

# Initialize application
proc initialize_talkie {} {
    # Load configuration
    ::config::load

    # Initialize GUI
    ::gui::initialize

    # Refresh audio devices
    ::device::refresh_devices

    # Start UI updates
    ::display::start_ui_updates

    # Initialize audio stream for energy monitoring
    ::audio::initialize

    puts "✓ Talkie Tcl Edition (Modular)"

    # Show default view after initialization
    after idle {
        ::gui::show_default_view
    }
}

# Start the application
initialize_talkie