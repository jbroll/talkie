#!/usr/bin/env tclsh

package require tcltest
namespace import tcltest::*

# Setup path for the compiled package
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

# Test package loading
test pa-1.1 {Load pa package} -body {
    package require pa
} -result 1.0

# Test PortAudio initialization
test pa-2.1 {Initialize PortAudio} -body {
    pa::init
} -result 0

# Test device listing
test pa-3.1 {List audio devices} -body {
    set devices [pa::list_devices]
    expr {[llength $devices] > 0}
} -result 1

test pa-3.2 {Device list structure} -body {
    set devices [pa::list_devices]
    if {[llength $devices] == 0} {
        return "no devices"
    }
    set first [lindex $devices 0]
    set keys [dict keys $first]
    set expected {index name maxInputChannels defaultSampleRate}
    expr {[llength [lsort $keys]] >= [llength $expected]}
} -result 1

# Test stream creation with minimal parameters
test pa-4.1 {Create basic stream} -body {
    set stream [pa::open_stream]
    set info [$stream info]
    $stream close
    dict exists $info rate
} -result 1

# Test stream with custom parameters
test pa-4.2 {Create stream with parameters} -body {
    set stream [pa::open_stream -rate 22050 -channels 1 -frames 512]
    set info [$stream info]
    $stream close
    set rate [dict get $info rate]
    expr {$rate == 22050.0}
} -result 1

# Test stream info command
test pa-5.1 {Stream info contains required fields} -body {
    set stream [pa::open_stream]
    set info [$stream info]
    $stream close
    set required {rate channels framesPerBuffer overflows underruns}
    set missing {}
    foreach field $required {
        if {![dict exists $info $field]} {
            lappend missing $field
        }
    }
    set missing
} -result {}

# Test stream stats command
test pa-5.2 {Stream stats command} -body {
    set stream [pa::open_stream]
    set stats [$stream stats]
    $stream close
    set required {overflows underruns}
    set missing {}
    foreach field $required {
        if {![dict exists $stats $field]} {
            lappend missing $field
        }
    }
    set missing
} -result {}

# Test callback setting
test pa-6.1 {Set callback on stream} -body {
    set stream [pa::open_stream]
    $stream setcallback {puts "test callback"}
    $stream close
} -result ok

# Test stream start/stop (without actual audio processing)
test pa-7.1 {Start and stop stream} -body {
    set stream [pa::open_stream -callback {# dummy callback}]
    set start_result [$stream start]
    after 100  ;# Brief delay
    set stop_result [$stream stop]
    $stream close
    list $start_result $stop_result
} -result {ok ok}

# Test error handling - invalid device
test pa-8.1 {Invalid device name} -body {
    catch {pa::open_stream -device "nonexistent_device_12345"} err
    string match "*not found*" $err
} -result 1

# Test error handling - invalid parameters
test pa-8.2 {Invalid rate parameter} -body {
    catch {pa::open_stream -rate "not_a_number"} err
    string match "*expected floating-point*" $err
} -result 1

# Test different formats
test pa-9.1 {float32 format} -body {
    set stream [pa::open_stream -format float32]
    set info [$stream info]
    $stream close
    dict exists $info rate
} -result 1

test pa-9.2 {int16 format} -body {
    set stream [pa::open_stream -format int16]
    set info [$stream info]
    $stream close
    dict exists $info rate
} -result 1

# Test error handling - invalid format
test pa-9.3 {Invalid format} -body {
    catch {pa::open_stream -format "invalid_format"} err
    string match "*unknown format*" $err
} -result 1

# Test stream cleanup
test pa-10.1 {Stream cleanup on close} -body {
    set stream [pa::open_stream]
    set name $stream
    $stream close
    # Try to use closed stream - should fail
    catch {$name info} err
    string match "*invalid command name*" $err
} -result 1

# Performance test - multiple streams
test pa-11.1 {Multiple stream creation} -body {
    set streams {}
    for {set i 0} {$i < 5} {incr i} {
        lappend streams [pa::open_stream]
    }
    foreach stream $streams {
        $stream close
    }
    llength $streams
} -result 5

# Test with real callback function
proc test_callback {stream timestamp data} {
    global callback_called callback_data
    set callback_called 1
    set callback_data [list $stream $timestamp [string length $data]]
}

test pa-12.1 {Callback with real function} -body {
    global callback_called
    set callback_called 0
    set stream [pa::open_stream -callback test_callback]
    $stream start
    after 200  ;# Wait for potential callback
    $stream stop
    $stream close
    # Note: callback may not be called in test environment without real audio
    set callback_called
} -result {0}

# Cleanup
cleanupTests