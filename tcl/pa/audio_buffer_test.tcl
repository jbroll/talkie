#!/usr/bin/env tclsh

# Test actual audio buffer reception from PortAudio stream
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

package require pa
Pa_Init

puts "Testing actual audio buffer reception..."

# Global variables to track callback data
set ::callback_count 0
set ::total_bytes 0
set ::buffer_sizes {}
set ::timestamps {}

# Callback function to process audio data
proc audio_callback {stream timestamp data} {
    incr ::callback_count
    set bytes [string length $data]
    incr ::total_bytes $bytes
    lappend ::buffer_sizes $bytes
    lappend ::timestamps $timestamp

    puts "Callback $::callback_count: $bytes bytes at timestamp $timestamp"

    # Stop after receiving a reasonable amount of data
    if {$::callback_count >= 20} {
        puts "Received enough samples, stopping..."
        $stream stop
    }
}

puts "Creating audio stream with callback..."
set stream [pa::open_stream -device default -rate 44100 -channels 1 -frames 256 -format float32 -callback audio_callback]

puts "Stream created: $stream"
puts "Stream info: [$stream info]"

puts "Starting audio capture..."
$stream start

# Wait for callbacks to be received
puts "Waiting for audio data..."
set timeout 0
while {$::callback_count < 20 && $timeout < 100} {
    after 100
    incr timeout
    if {$timeout % 10 == 0} {
        puts "Still waiting... callbacks received: $::callback_count"
    }
}

puts "Stopping stream..."
$stream stop
$stream close

puts "\n=== AUDIO BUFFER TEST RESULTS ==="
puts "Total callbacks received: $::callback_count"
puts "Total bytes processed: $::total_bytes"

if {$::callback_count > 0} {
    puts "Average buffer size: [expr {$::total_bytes / $::callback_count}] bytes"
    puts "Buffer sizes: [lrange $::buffer_sizes 0 4]..."
    puts "Timestamps: [lrange $::timestamps 0 4]..."

    # Verify buffer consistency
    set expected_size [expr {256 * 1 * 4}]  ; # frames * channels * sizeof(float32)
    set first_size [lindex $::buffer_sizes 0]
    if {$first_size == $expected_size} {
        puts "✓ Buffer size matches expected: $expected_size bytes"
    } else {
        puts "✗ Buffer size mismatch: got $first_size, expected $expected_size"
    }

    # Check if we got real-time data
    if {$::callback_count >= 10} {
        puts "✓ Successfully received real-time audio buffers!"
    } else {
        puts "✗ Insufficient audio data received"
    }
} else {
    puts "✗ No audio callbacks were received"
    puts "This could indicate:"
    puts "  - No audio input device available"
    puts "  - Audio system permissions issues"
    puts "  - Hardware/driver problems"
}

puts "\nTest completed."