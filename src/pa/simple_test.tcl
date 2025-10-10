#!/usr/bin/env tclsh

# Simple test to debug the PortAudio binding
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Testing PortAudio binding..."

# Test 1: Load package
puts -nonewline "Loading pa package... "
if {[catch {package require pa} err]} {
    puts "FAILED: $err"
    exit 1
}
puts "OK (version: $err)"

# Test 2: Initialize PortAudio
puts -nonewline "Initializing PortAudio... "
if {[catch {pa::init} err]} {
    puts "FAILED: $err"
    exit 1
}
puts "OK"

# Test 3: List devices
puts -nonewline "Listing devices... "
if {[catch {pa::list_devices} devices]} {
    puts "FAILED: $devices"
    exit 1
}
puts "OK ([llength $devices] devices found)"

if {[llength $devices] > 0} {
    puts "First device: [lindex $devices 0]"
}

puts "Basic tests completed successfully!"