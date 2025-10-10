#!/usr/bin/env tclsh

# Final working test of the PortAudio binding
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Testing PortAudio Critcl binding..."

# Test 1: Load package
puts -nonewline "Loading pa package... "
if {[catch {package require pa} err]} {
    puts "FAILED: $err"
    exit 1
}
puts "OK (version: $err)"

# Test 2: Call Pa_Init to register commands
puts -nonewline "Calling Pa_Init to register commands... "
if {[catch {Pa_Init} err]} {
    puts "FAILED: $err"
    exit 1
}
puts "OK"

# Test 3: Initialize PortAudio
puts -nonewline "Initializing PortAudio... "
if {[catch {pa::init} err]} {
    puts "FAILED: $err"
    exit 1
}
puts "OK"

# Test 4: List devices
puts -nonewline "Listing audio devices... "
if {[catch {pa::list_devices} devices]} {
    puts "FAILED: $devices"
    exit 1
}
puts "OK ([llength $devices] devices found)"

if {[llength $devices] > 0} {
    puts "First device info:"
    foreach {key value} [lindex $devices 0] {
        puts "  $key: $value"
    }
}

# Test 5: Create and test a stream
puts -nonewline "Creating audio stream... "
if {[catch {pa::open_stream -rate 22050 -channels 1 -frames 256} stream]} {
    puts "FAILED: $stream"
    exit 1
}
puts "OK (stream: $stream)"

# Test 6: Get stream info
puts -nonewline "Getting stream info... "
if {[catch {$stream info} info]} {
    puts "FAILED: $info"
    $stream close
    exit 1
}
puts "OK"
puts "Stream info:"
foreach {key value} $info {
    puts "  $key: $value"
}

# Test 7: Get stats
puts -nonewline "Getting stream stats... "
if {[catch {$stream stats} stats]} {
    puts "FAILED: $stats"
    $stream close
    exit 1
}
puts "OK"
puts "Stream stats:"
foreach {key value} $stats {
    puts "  $key: $value"
}

# Test 8: Clean up
puts -nonewline "Closing stream... "
if {[catch {$stream close} err]} {
    puts "FAILED: $err"
    exit 1
}
puts "OK"

puts ""
puts "✓ All tests passed! PortAudio Critcl binding is working correctly."