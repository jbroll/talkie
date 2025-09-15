#!/usr/bin/env tclsh

# Test the fixed package
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Loading pa package..."
package require pa
puts "✓ Package loaded"

puts "\nCalling pa::init..."
pa::init
puts "✓ pa::init called"

puts "\nChecking available commands..."
set pa_commands [info commands pa::*]
puts "Available pa:: commands: $pa_commands"

if {[info commands pa::list_devices] ne ""} {
    puts "\n✓ pa::list_devices is available!"
    puts "Testing device listing..."
    set devices [pa::list_devices]
    puts "✓ Found [llength $devices] devices"

    if {[llength $devices] > 0} {
        puts "\nFirst few devices:"
        for {set i 0} {$i < [expr {min(3, [llength $devices])}]} {incr i} {
            set device [lindex $devices $i]
            dict with device {
                puts "  $index: $name (inputs: $maxInputChannels)"
            }
        }
    }
} else {
    puts "\n✗ pa::list_devices still not found"
}

puts "\nDone!"