#!/usr/bin/env tclsh

# Debug test to see exactly what's happening with package loading
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Step 1: Loading pa package..."
package require pa
puts "✓ Package loaded"

puts "\nStep 2: Checking available commands..."
set all_pa_commands [info commands pa::*]
puts "Available pa:: commands: $all_pa_commands"

set all_Pa_commands [info commands Pa_*]
puts "Available Pa_ commands: $all_Pa_commands"

puts "\nStep 3: Testing pa::init..."
if {[info commands pa::init] ne ""} {
    set result [pa::init]
    puts "✓ pa::init result: $result"
} else {
    puts "✗ pa::init not found"
}

puts "\nStep 4: Manually calling Pa_Init..."
if {[info commands Pa_Init] ne ""} {
    puts "Calling Pa_Init..."
    Pa_Init
    puts "✓ Pa_Init called"

    puts "\nStep 5: Checking commands again..."
    set new_pa_commands [info commands pa::*]
    puts "Available pa:: commands after Pa_Init: $new_pa_commands"

    if {[info commands pa::list_devices] ne ""} {
        puts "✓ pa::list_devices now available!"
        set devices [pa::list_devices]
        puts "Found [llength $devices] devices"
    } else {
        puts "✗ pa::list_devices still not found"
    }
} else {
    puts "✗ Pa_Init not found"
}

puts "\nDone."