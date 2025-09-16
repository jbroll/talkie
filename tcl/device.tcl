# device.tcl - Audio device management for Talkie

namespace eval ::device {

    proc refresh_devices {} {
        if {[catch {
            set devices [pa::list_devices]
            set input_devices {}
            set default_found false

            foreach device $devices {
                if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                    set device_name [dict get $device name]
                    lappend input_devices $device_name

                    # Check for pulse device
                    if {$device_name eq "pulse" || [string match "*pulse*" $device_name]} {
                        set ::config::config(device) $device_name
                        set default_found true
                    }
                }
            }

            # Update UI if it exists
            if {[winfo exists .controls_frame.container.device.control.mb.menu]} {
                set device_menu .controls_frame.container.device.control.mb.menu
                # Clear and populate dropdown menu
                $device_menu delete 0 end
                foreach device $input_devices {
                    $device_menu add command -label $device -command [list ::device::device_selected $device]
                }

                # Set current device - dropdown is bound directly to config
                if {!$default_found && [llength $input_devices] > 0} {
                    # If no pulse device found, use first available
                    set ::config::config(device) [lindex $input_devices 0]
                }
            }
        } err]} {
            puts "Error refreshing devices: $err"
        }
    }

    proc device_selected {device} {
        set ::config::config(device) $device
    }
}