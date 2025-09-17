# device.tcl - Audio device management for Talkie

namespace eval ::device {
    proc refresh_devices {} {
        if {[catch {
            set ::input_devices {}
            set preferred $::config(input_device)
            set found_preferred false

            foreach device [pa::list_devices] {
                if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                    set name [dict get $device name]
                    lappend ::input_devices $name
                    if {$name eq $preferred || [string match "*$preferred*" $name]} {
                        set ::config(input_device) $name
                        set found_preferred true
                    }
                }
            }

            if {!$found_preferred && [llength $::input_devices] > 0} {
                set ::config(input_device) [lindex $::input_devices 0]
            }
        } err]} {
            puts "Error refreshing devices: $err"
        }
    }
}
