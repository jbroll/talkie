# device_layout.tcl - Audio device management for Layout-based Talkie

namespace eval ::device {

    proc refresh_devices {args} {
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
                        ::gui::set_ui_element device $device_name
                        set default_found true
                    }
                }
            }

            # Update GUI device list
            ::gui::update_device_list $input_devices

            # Set current device if not found
            if {!$default_found && [llength $input_devices] > 0} {
                # If no pulse device found, use first available
                set first_device [lindex $input_devices 0]
                ::config::set_value device $first_device
                ::gui::set_ui_element device $first_device
            }

        } err]} {
            puts "Error refreshing devices: $err"
        }
    }

    proc device_selected {device} {
        ::config::set_value device $device
        ::gui::set_ui_element device $device
    }
}
