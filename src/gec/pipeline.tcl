# pipeline.tcl - GEC pipeline combining punctuation/capitalization, homophone, and grammar correction
#
# Pipeline stages:
# 1. homophone: Fix homophones using masked language modeling (ELECTRA/NPU)
# 2. punctcap: Restore punctuation and capitalization (DistilBERT/NPU)
# 3. grammar: Fix subject-verb agreement, tense, articles (T5/CPU)
#
# Usage:
#   gec_pipeline::init -punctcap_model PATH -homophone_model PATH -grammar_model PATH -vocab PATH [-device NPU]
#   set corrected [gec_pipeline::process $text]
#   gec_pipeline::cleanup

package require gec
package require wordpiece

namespace eval gec_pipeline {
    variable initialized 0
    variable punct_enabled 1
    variable homo_enabled 1
    variable grammar_enabled 1
    variable stats
    variable last_timing
    variable script_dir
    array set stats {processed 0 punct_changes 0 homo_changes 0 grammar_changes 0 total_ms 0}
    array set last_timing {homo_ms 0 punct_ms 0 grammar_ms 0 total_ms 0}
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
    set grammar_model ""
    set vocab_path ""
    set homophones_path ""
    set device "NPU"

    foreach {opt val} $args {
        switch -- $opt {
            -punctcap_model { set punctcap_model $val }
            -homophone_model { set homophone_model $val }
            -grammar_model { set grammar_model $val }
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

    # Initialize grammar correction module (optional - T5 on CPU)
    if {$grammar_model ne ""} {
        puts stderr "gec_pipeline: Loading grammar model..."
        source [file join $script_dir grammar.tcl]
        grammar::init -model $grammar_model
    }

    # Reset stats
    array set stats {processed 0 punct_changes 0 homo_changes 0 grammar_changes 0 total_ms 0}

    set initialized 1
    puts stderr "gec_pipeline: Initialized ($homo_count homophone groups)"
    return 1
}

# Process text through the GEC pipeline
# Order: homophone (raw text) -> punctcap (formatting) -> grammar (T5 corrections)
proc gec_pipeline::process {text} {
    variable initialized
    variable punct_enabled
    variable homo_enabled
    variable grammar_enabled
    variable stats
    variable last_timing

    if {!$initialized} {
        error "gec_pipeline::init must be called first"
    }

    if {$text eq ""} {
        array set last_timing {homo_ms 0 punct_ms 0 grammar_ms 0 total_ms 0}
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

    # Stage 2: Punctuation and capitalization restoration
    set punct_start [clock microseconds]
    if {$punct_enabled} {
        set text [punctcap::restore $text]
    }
    set punct_us [expr {[clock microseconds] - $punct_start}]
    set after_punct $text

    # Stage 3: Grammar correction (T5 on CPU)
    set grammar_start [clock microseconds]
    if {$grammar_enabled && [info commands grammar::correct] ne ""} {
        set text [grammar::correct $text]
    }
    set grammar_us [expr {[clock microseconds] - $grammar_start}]

    # Track per-call timing
    set elapsed_us [expr {[clock microseconds] - $start_us}]
    set last_timing(homo_ms) [expr {$homo_us / 1000.0}]
    set last_timing(punct_ms) [expr {$punct_us / 1000.0}]
    set last_timing(grammar_ms) [expr {$grammar_us / 1000.0}]
    set last_timing(total_ms) [expr {$elapsed_us / 1000.0}]

    # Track cumulative statistics
    incr stats(processed)
    incr stats(total_ms) [expr {$elapsed_us / 1000}]
    if {$after_homo ne $original} {
        incr stats(homo_changes)
    }
    if {$after_punct ne $after_homo} {
        incr stats(punct_changes)
    }
    if {$text ne $after_punct} {
        incr stats(grammar_changes)
    }

    return $text
}

# Process with verbose output for debugging
proc gec_pipeline::process_verbose {text} {
    variable initialized
    variable punct_enabled
    variable homo_enabled
    variable grammar_enabled

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

    # Stage 2: Punctuation and capitalization
    if {$punct_enabled} {
        set punct_result [punctcap::restore $current]
        dict set result punct_output $punct_result
        dict set result punct_changed [expr {$punct_result ne $current}]
        set current $punct_result
    }

    # Stage 3: Grammar correction (T5)
    if {$grammar_enabled && [info commands grammar::correct] ne ""} {
        set grammar_result [grammar::correct $current]
        dict set result grammar_output $grammar_result
        dict set result grammar_changed [expr {$grammar_result ne $current}]
        set current $grammar_result
    }

    dict set result output $current
    return $result
}

# Enable/disable pipeline stages
proc gec_pipeline::configure {args} {
    variable punct_enabled
    variable homo_enabled
    variable grammar_enabled

    foreach {opt val} $args {
        switch -- $opt {
            -punct { set punct_enabled $val }
            -homophone { set homo_enabled $val }
            -grammar { set grammar_enabled $val }
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
        grammar_changes $stats(grammar_changes) \
        total_ms $stats(total_ms) \
        avg_ms $avg_ms]
}

# Get timing from last process call (in milliseconds)
proc gec_pipeline::last_timing {} {
    variable last_timing
    return [dict create \
        homo_ms $last_timing(homo_ms) \
        punct_ms $last_timing(punct_ms) \
        grammar_ms $last_timing(grammar_ms) \
        total_ms $last_timing(total_ms)]
}

# Clean up resources
proc gec_pipeline::cleanup {} {
    variable initialized

    if {$initialized} {
        catch { punctcap::cleanup }
        catch { homophone::cleanup }
        catch { grammar::cleanup }
        set initialized 0
    }
}

package provide gec_pipeline 1.0
