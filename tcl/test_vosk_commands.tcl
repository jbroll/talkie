#!/usr/bin/env tclsh
# Test what Vosk commands are actually available

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir vosk lib]

puts "=== Testing Vosk Command Discovery ==="

puts "Step 1: Loading Vosk package..."
if {[catch {
    package require vosk
    puts "✓ Vosk package loaded: [package present vosk]"
} err]} {
    puts "✗ Failed to load Vosk: $err"
    exit 1
}

puts "\nStep 2: Checking available commands..."
puts "Commands starting with 'vosk':"
foreach cmd [lsort [info commands vosk*]] {
    puts "  $cmd"
}

puts "\nCommands starting with 'Vosk':"
foreach cmd [lsort [info commands Vosk*]] {
    puts "  $cmd"
}

puts "\nAll commands containing 'vosk' or 'Vosk':"
foreach cmd [lsort [info commands]] {
    if {[string match "*vosk*" [string tolower $cmd]]} {
        puts "  $cmd"
    }
}

puts "\nStep 3: Testing command execution..."
foreach test_cmd {Vosk_Init vosk::init vosk_init} {
    if {[info commands $test_cmd] ne ""} {
        puts "Found command: $test_cmd"
        if {[catch {
            $test_cmd
            puts "✓ $test_cmd executed successfully"
        } err]} {
            puts "✗ $test_cmd failed: $err"
        }
    }
}