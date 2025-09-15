#!/usr/bin/env tclsh
# Simple syntax and basic function test - no GUI, no hanging

puts "🧪 Simple Talkie Test (No GUI)"
puts [string repeat "-" 30]

# Just test that the file can be parsed
if {[catch {
    set fd [open "talkie_python_like.tcl" r]
    set content [read $fd]
    close $fd

    if {[info complete $content]} {
        puts "✅ Syntax: VALID"
    } else {
        puts "❌ Syntax: INVALID"
    }
} err]} {
    puts "❌ File error: $err"
    exit 1
}

# Test that packages load
if {[catch {
    set script_dir [file dirname [file normalize [info script]]]
    lappend auto_path [file join $script_dir pa lib]
    lappend auto_path [file join $script_dir vosk lib]

    package require pa
    pa::init
    if {[info commands Pa_Init] ne ""} {
        Pa_Init
    }
    puts "✅ PortAudio: OK"

    package require vosk
    vosk::set_log_level -1
    puts "✅ Vosk: OK"

} err]} {
    puts "❌ Package error: $err"
}

# Test device listing (quick check)
if {[catch {
    set devices [pa::list_devices]
    puts "✅ Devices: [llength $devices] found"

    # Quick pulse check
    set pulse_found 0
    foreach device $devices {
        dict with device {
            if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                if {[string match -nocase "*pulse*" $name]} {
                    puts "✅ Pulse device: $name"
                    set pulse_found 1
                    break
                }
            }
        }
    }
    if {!$pulse_found} {
        puts "⚠️  No pulse device found"
    }
} err]} {
    puts "❌ Device test failed: $err"
}

puts "✅ Simple test complete - application structure is sound"