# pipeline.tcl - GEC pipeline combining punctuation/capitalization and homophone correction
#
# Pipeline stages:
# 1. punctcap: Restore punctuation and capitalization to raw Vosk output
# 2. homophone: Fix homophones using masked language modeling
#
# Usage:
#   gec_pipeline::init -punctcap_model PATH -homophone_model PATH -vocab PATH [-device NPU]
#   set corrected [gec_pipeline::process $text]
#   gec_pipeline::cleanup

package require gec
package require wordpiece

namespace eval gec_pipeline {
    variable initialized 0
    variable punct_enabled 1
    variable homo_enabled 1
    variable stats
    variable last_timing
    variable script_dir
    array set stats {processed 0 punct_changes 0 homo_changes 0 total_ms 0}
    array set last_timing {homo_ms 0 punct_ms 0 total_ms 0}
}

# Capture script directory at load time (before any procs are called)
# This must be done here because [info script] changes when other files are sourced
set gec_pipeline::script_dir [file dirname [file normalize [info script]]]

# Initialize the GEC pipeline
proc gec_pipeline::init {args} {
    variable initialized
    variable stats
    variable script_dir

    # Parse arguments
    set punctcap_model ""
    set homophone_model ""
    set vocab_path ""
    set homophones_path ""
    set device "NPU"

    foreach {opt val} $args {
        switch -- $opt {
            -punctcap_model { set punctcap_model $val }
            -homophone_model { set homophone_model $val }
            -vocab { set vocab_path $val }
            -homophones { set homophones_path $val }
            -device { set device $val }
            default { error "Unknown option: $opt" }
        }
    }

    # Validate required options
    if {$punctcap_model eq ""} {
        error "Missing required -punctcap_model option"
    }
    if {$homophone_model eq ""} {
        error "Missing required -homophone_model option"
    }
    if {$vocab_path eq ""} {
        error "Missing required -vocab option"
    }

    # Default homophones path
    if {$homophones_path eq ""} {
        set homophones_path [file normalize [file join [file dirname $homophone_model] ../../data/homophones.json]]
    }

    # Load shared vocabulary
    wordpiece::load $vocab_path

    # Initialize punctuation/capitalization module
    puts stderr "gec_pipeline: Loading punctcap model..."
    source [file join $script_dir punctcap.tcl]
    punctcap::init -model $punctcap_model -vocab $vocab_path -device $device

    # Initialize homophone correction module
    puts stderr "gec_pipeline: Loading homophone model..."
    source [file join $script_dir homophone.tcl]
    set homo_count [homophone::init -model $homophone_model -vocab $vocab_path \
        -homophones $homophones_path -device $device]

    # Reset stats
    array set stats {processed 0 punct_changes 0 homo_changes 0 total_ms 0}

    set initialized 1
    puts stderr "gec_pipeline: Initialized ($homo_count homophone groups)"
    return 1
}

# Process text through the GEC pipeline
# Order: homophone correction FIRST (on raw lowercase text), then punctcap (adds caps/punct)
proc gec_pipeline::process {text} {
    variable initialized
    variable punct_enabled
    variable homo_enabled
    variable stats
    variable last_timing

    if {!$initialized} {
        error "gec_pipeline::init must be called first"
    }

    if {$text eq ""} {
        array set last_timing {homo_ms 0 punct_ms 0 total_ms 0}
        return ""
    }

    set start_us [clock microseconds]
    set original $text

    # Stage 1: Homophone correction (works on raw lowercase Vosk output)
    set homo_start [clock microseconds]
    if {$homo_enabled} {
        set text [homophone::correct $text]
    }
    set homo_us [expr {[clock microseconds] - $homo_start}]
    set after_homo $text

    # Stage 2: Punctuation and capitalization restoration (final formatting)
    set punct_start [clock microseconds]
    if {$punct_enabled} {
        set text [punctcap::restore $text]
    }
    set punct_us [expr {[clock microseconds] - $punct_start}]

    # Track per-call timing
    set elapsed_us [expr {[clock microseconds] - $start_us}]
    set last_timing(homo_ms) [expr {$homo_us / 1000.0}]
    set last_timing(punct_ms) [expr {$punct_us / 1000.0}]
    set last_timing(total_ms) [expr {$elapsed_us / 1000.0}]

    # Track cumulative statistics
    incr stats(processed)
    incr stats(total_ms) [expr {$elapsed_us / 1000}]
    if {$after_homo ne $original} {
        incr stats(homo_changes)
    }
    if {$text ne $after_homo} {
        incr stats(punct_changes)
    }

    return $text
}

# Process with verbose output for debugging
proc gec_pipeline::process_verbose {text} {
    variable initialized
    variable punct_enabled
    variable homo_enabled

    if {!$initialized} {
        error "gec_pipeline::init must be called first"
    }

    set result [dict create input $text]
    set current $text

    # Stage 1: Homophone correction (on raw text)
    if {$homo_enabled} {
        set homo_result [homophone::correct $current]
        dict set result homo_output $homo_result
        dict set result homo_changed [expr {$homo_result ne $current}]
        set current $homo_result
    }

    # Stage 2: Punctuation and capitalization (final formatting)
    if {$punct_enabled} {
        set punct_result [punctcap::restore $current]
        dict set result punct_output $punct_result
        dict set result punct_changed [expr {$punct_result ne $current}]
        set current $punct_result
    }

    dict set result output $current
    return $result
}

# Enable/disable pipeline stages
proc gec_pipeline::configure {args} {
    variable punct_enabled
    variable homo_enabled

    foreach {opt val} $args {
        switch -- $opt {
            -punct { set punct_enabled $val }
            -homophone { set homo_enabled $val }
            default { error "Unknown option: $opt" }
        }
    }
}

# Get pipeline statistics
proc gec_pipeline::stats {} {
    variable stats

    set avg_ms 0
    if {$stats(processed) > 0} {
        set avg_ms [expr {double($stats(total_ms)) / $stats(processed)}]
    }

    return [dict create \
        processed $stats(processed) \
        punct_changes $stats(punct_changes) \
        homo_changes $stats(homo_changes) \
        total_ms $stats(total_ms) \
        avg_ms $avg_ms]
}

# Get timing from last process call (in milliseconds)
proc gec_pipeline::last_timing {} {
    variable last_timing
    return [dict create \
        homo_ms $last_timing(homo_ms) \
        punct_ms $last_timing(punct_ms) \
        total_ms $last_timing(total_ms)]
}

# Clean up resources
proc gec_pipeline::cleanup {} {
    variable initialized

    if {$initialized} {
        catch { punctcap::cleanup }
        catch { homophone::cleanup }
        set initialized 0
    }
}

package provide gec_pipeline 1.0
