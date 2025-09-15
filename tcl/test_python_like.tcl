#!/usr/bin/env tclsh
# Quick test of the Python-like functionality

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir vosk lib]

puts "Testing Python-like Talkie functionality..."

# Load packages
if {[catch {
    package require pa
    pa::init

    # Manually call Pa_Init to register additional commands
    if {[info commands Pa_Init] ne ""} {
        Pa_Init
        puts "✓ PortAudio loaded and initialized"
    } else {
        puts "✓ PortAudio loaded (Pa_Init not available)"
    }
} err]} {
    puts "✗ PortAudio error: $err"
    exit 1
}

# Test device listing and pulse selection
puts "\nTesting device selection..."
if {[catch {
    set devices [pa::list_devices]
    puts "✓ Found [llength $devices] total devices"

    set input_devices {}
    set pulse_device ""

    foreach device $devices {
        dict with device {
            if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                set display_name "$name (ID: $index)"
                lappend input_devices [list $display_name $index $name]

                # Look for pulse device (matching Python logic)
                if {[string match -nocase "*pulse*" $name]} {
                    set pulse_device $display_name
                    puts "✓ Found pulse device: $name"
                }
            }
        }
    }

    puts "✓ Found [llength $input_devices] input devices"

    if {$pulse_device eq ""} {
        puts "! No pulse device found, would use first available:"
        if {[llength $input_devices] > 0} {
            set first_device [lindex [lindex $input_devices 0] 0]
            puts "  Default: $first_device"
        }
    } else {
        puts "✓ Default pulse device: $pulse_device"
    }

} err]} {
    puts "✗ Device test error: $err"
}

# Test Vosk
puts "\nTesting Vosk package..."
if {[catch {
    package require vosk
    vosk::set_log_level -1
    puts "✓ Vosk loaded and configured"

    set model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
    if {[file exists $model_path]} {
        puts "✓ Vosk model available at: $model_path"
    } else {
        puts "! Vosk model not found at: $model_path"
    }
} err]} {
    puts "✗ Vosk error: $err"
}

puts "\n✓ Python-like functionality test completed!"
puts "Ready to run full GUI application."