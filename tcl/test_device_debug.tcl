#!/usr/bin/env tclsh
# Quick test of device loading

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]

# Load PortAudio
package require pa
pa::init
if {[info commands Pa_Init] ne ""} {
    Pa_Init
}

# Test device listing directly
puts "Testing device listing..."

set devices [pa::list_devices]
puts "Total devices found: [llength $devices]"

set input_devices {}
foreach device $devices {
    dict with device {
        if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
            set display_name "$name (ID: $index)"
            lappend input_devices [list $display_name $index $name]
            puts "Input device: $display_name"
        }
    }
}

puts "Total input devices: [llength $input_devices]"

if {[llength $input_devices] == 0} {
    puts "❌ No input devices found!"
} else {
    puts "✅ Input devices found"
    foreach device_info $input_devices {
        lassign $device_info display_name device_id device_name
        puts "  - $display_name"
    }
}