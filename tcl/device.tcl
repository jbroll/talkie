# device.tcl - Audio device management for Talkie

namespace eval ::device {

    proc refresh_devices {} {
        if {[catch {
            set devices [pa::list_devices]
            set ::input_devices {}
            set default_found false

            foreach device $devices {
                if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                    set device_name [dict get $device name]
                    lappend ::input_devices $device_name

                    # Check for pulse device
                    if {$device_name eq "pulse" || [string match "*pulse*" $device_name]} {
                        set ::config(input_device) $device_name
                        set default_found true
                    }
                }
            }

            # If no pulse device found, use first available
            if {!$default_found && [llength $::input_devices] > 0} {
                set ::config(input_device) [lindex $::input_devices 0]
            }

        } err]} {
            puts "Error refreshing devices: $err"
        }
    }
}
