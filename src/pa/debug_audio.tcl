#!/usr/bin/env tclsh

# Debug audio stream and investigate callback issues
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

package require pa
Pa_Init

puts "=== AUDIO DEBUGGING ==="

# List available devices with detailed info
puts "\nAvailable audio devices:"
set devices [pa::list_devices]
for {set i 0} {$i < [llength $devices]} {incr i} {
    set dev [lindex $devices $i]
    puts "Device $i:"
    foreach {key value} $dev {
        puts "  $key: $value"
    }
    puts ""
}

# Test different device configurations
set test_devices {"default"}

# Add specific device names that might work better
foreach dev $devices {
    set name [dict get $dev name]
    set maxInput [dict get $dev maxInputChannels]
    if {$maxInput > 0 && [string match "*hw:*" $name]} {
        lappend test_devices $name
        break
    }
}

foreach device_name $test_devices {
    puts "Testing device: $device_name"

    if {[catch {
        set stream [pa::open_stream -device $device_name -rate 44100 -channels 1 -frames 128 -format float32 -callback {
            puts "CALLBACK TRIGGERED: [string length $data] bytes"
        }]

        puts "  Stream created successfully: $stream"
        puts "  Stream info: [$stream info]"

        # Try to start stream
        if {[catch {$stream start} err]} {
            puts "  ✗ Failed to start stream: $err"
        } else {
            puts "  ✓ Stream started"

            # Wait briefly and check stats
            after 200
            set stats [$stream stats]
            puts "  Stream stats: $stats"

            # Stop stream
            $stream stop
            puts "  ✓ Stream stopped"
        }

        $stream close

    } err]} {
        puts "  ✗ Failed to create/test stream: $err"
    }
    puts ""
}

# Test with minimal parameters to see if that helps
puts "Testing with minimal parameters..."
if {[catch {
    set stream [pa::open_stream -rate 8000 -channels 1 -frames 64 -format int16]
    puts "Minimal stream created: [$stream info]"

    # Test without starting - just creation
    $stream close
    puts "✓ Minimal stream test passed"

} err]} {
    puts "✗ Minimal stream test failed: $err"
}

puts "\n=== DEBUG COMPLETE ==="