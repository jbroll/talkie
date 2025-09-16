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
                        ::config::set_value device $device_name
                        set default_found true
                    }
                }
            }

            # Update UI if it exists
            set device_menu [::gui::get_ui_element device_menu]
            if {$device_menu ne ""} {
                # Clear and populate dropdown menu
                $device_menu delete 0 end
                foreach device $input_devices {
                    $device_menu add command -label $device -command [list ::device::device_selected $device]
                }

                # Set current device
                if {$default_found} {
                    ::gui::set_ui_var device_var [::config::get device]
                } elseif {[llength $input_devices] > 0} {
                    # If no pulse device found, use first available
                    ::config::set_value device [lindex $input_devices 0]
                    ::gui::set_ui_var device_var [::config::get device]
                }
            }
        } err]} {
            puts "Error refreshing devices: $err"
        }
    }

    proc device_selected {device} {
        ::config::set_value device $device
        ::gui::set_ui_var device_var $device
    }
}