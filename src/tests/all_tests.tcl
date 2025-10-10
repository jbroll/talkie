#!/usr/bin/env tclsh
# Test runner for Talkie tests

package require tcltest
namespace import ::tcltest::*

# Configure test output
configure -verbose {pass skip start}

# Add mock modules to auto_path
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir mocks]

# Set up the test directory
configure -testdir $script_dir

# Run all test files
set test_files [glob -nocomplain [file join $script_dir *.test]]

# Run tests and cleanup
runAllTests
cleanupTests