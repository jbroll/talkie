#!/usr/bin/env tclsh
# test_integration.tcl - Integration test for Talkie Tcl components

package require Tcl 8.6

# Test configuration
set script_dir [file dirname [file normalize [info script]]]
set test_results {}

proc test_result {name success details} {
    global test_results
    lappend test_results [list $name $success $details]
    if {$success} {
        puts "✓ $name"
    } else {
        puts "✗ $name: $details"
    }
}

proc run_tests {} {
    global script_dir

    puts "Talkie Tcl Integration Tests"
    puts "============================\n"

    # Test 1: PortAudio package loading
    puts "Testing PortAudio package..."
    if {[catch {
        lappend auto_path [file join $script_dir pa lib]
        set ::env(TCLLIBPATH) "$::env(HOME)/.local/lib"
        package require pa
        set version [package present pa]
    } error]} {
        test_result "PortAudio package load" false $error
    } else {
        test_result "PortAudio package load" true "Version: $version"
    }

    # Test 2: PortAudio initialization
    puts "Testing PortAudio initialization..."
    if {[catch {
        set result [pa::init]
    } error]} {
        test_result "PortAudio initialization" false $error
    } else {
        if {$result == 0} {
            test_result "PortAudio initialization" true "Successfully initialized"
        } else {
            test_result "PortAudio initialization" false "Returned: $result"
        }
    }

    # Test 3: Device enumeration
    puts "Testing device enumeration..."
    if {[catch {
        set devices [pa::list_devices]
        set device_count [llength $devices]
    } error]} {
        test_result "Device enumeration" false $error
    } else {
        test_result "Device enumeration" true "Found $device_count devices"

        # Print device details
        foreach device $devices {
            dict with device {
                if {[dict exists $device maxInputChannels]} {
                    puts "  Device $index: $name ([dict get $device maxInputChannels] input channels)"
                }
            }
        }
    }

    # Test 4: Vosk package loading
    puts "\nTesting Vosk package..."
    if {[catch {
        lappend auto_path [file join $script_dir vosk lib]
        package require vosk
        set version [package present vosk]
    } error]} {
        test_result "Vosk package load" false $error
    } else {
        test_result "Vosk package load" true "Version: $version"
    }

    # Test 5: Vosk initialization (if model exists)
    set model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
    if {[file exists $model_path]} {
        puts "Testing Vosk initialization..."
        if {[catch {
            vosk::set_log_level -1
            set model [vosk::load_model -path $model_path]
        } error]} {
            test_result "Vosk initialization" false $error
        } else {
            if {$model ne ""} {
                test_result "Vosk initialization" true "Model loaded: $model_path"
                # Cleanup
                catch {$model destroy}
            } else {
                test_result "Vosk initialization" false "Model load returned empty"
            }
        }
    } else {
        test_result "Vosk initialization" false "Model not found: $model_path"
    }

    # Test 6: Interpreter creation
    puts "Testing interpreter creation..."
    if {[catch {
        set test_interp [interp create test_worker]
        $test_interp eval "set test_var 42"
        set result [$test_interp eval "return \$test_var"]
        interp delete $test_interp
    } error]} {
        test_result "Interpreter creation" false $error
    } else {
        if {$result == 42} {
            test_result "Interpreter creation" true "Worker interpreter functional"
        } else {
            test_result "Interpreter creation" false "Unexpected result: $result"
        }
    }

    # Test 7: JSON processing (for config)
    puts "Testing JSON processing..."
    if {[catch {
        package require json
        set test_data {{"key": "value", "number": 42}}
        set parsed [::json::json2dict $test_data]
        set rebuilt [::json::dict2json $parsed]
    } error]} {
        test_result "JSON processing" false $error
    } else {
        test_result "JSON processing" true "Parse and rebuild successful"
    }

    # Test 8: Tk availability (for GUI)
    puts "Testing Tk availability..."
    if {[catch {
        package require Tk
        set tk_version [package present Tk]
        # Create and destroy a test window
        toplevel .test_window
        destroy .test_window
    } error]} {
        test_result "Tk availability" false $error
    } else {
        test_result "Tk availability" true "Version: $tk_version"
    }

    # Cleanup
    puts "\nCleaning up..."
    if {[catch {
        pa::terminate
    } error]} {
        puts "Warning: Cleanup error: $error"
    }

    # Summary
    puts "\nTest Summary"
    puts "============"
    set total 0
    set passed 0
    foreach result $::test_results {
        lassign $result name success details
        incr total
        if {$success} {
            incr passed
        }
    }

    puts "Passed: $passed/$total tests"

    if {$passed == $total} {
        puts "All tests passed! ✓"
        return 0
    } else {
        puts "Some tests failed. ✗"
        return 1
    }
}

# Performance test
proc performance_test {} {
    puts "\nPerformance Tests"
    puts "================\n"

    # Test stream creation performance
    puts "Testing stream creation performance..."
    set start_time [clock milliseconds]

    # Create and destroy streams
    for {set i 0} {$i < 10} {incr i} {
        if {[catch {
            set stream [pa::open_stream -rate 16000 -channels 1 -frames 512]
            $stream close
        } error]} {
            puts "Performance test error: $error"
            break
        }
    }

    set end_time [clock milliseconds]
    set duration [expr {$end_time - $start_time}]

    puts "Created/destroyed 10 streams in ${duration}ms"
    puts "Average: [expr {$duration / 10.0}]ms per stream"
}

# Memory test
proc memory_test {} {
    puts "\nMemory Test"
    puts "==========="

    # This is a basic memory test - in production you'd use more sophisticated tools
    puts "Testing for obvious memory leaks..."

    set iterations 1000
    puts "Creating and destroying $iterations interpreters..."

    for {set i 0} {$i < $iterations} {incr i} {
        set test_interp [interp create test_$i]
        interp delete $test_interp

        if {$i % 100 == 0} {
            puts "  Completed $i/$iterations"
        }
    }

    puts "Memory test completed (check system memory usage)"
}

# Run tests based on command line arguments
proc main {argv} {
    switch -exact -- [lindex $argv 0] {
        "perf" {
            performance_test
        }
        "memory" {
            memory_test
        }
        "all" {
            set result [run_tests]
            performance_test
            memory_test
            return $result
        }
        default {
            return [run_tests]
        }
    }
    return 0
}

# Run if called directly
if {[info script] eq $argv0} {
    set result [main $argv]
    exit $result
}