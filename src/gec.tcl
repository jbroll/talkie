# gec.tcl - Grammar Error Correction integration for Talkie
#
# Provides homophone correction and punctuation/capitalization restoration
# for speech recognition output using neural network models.
#
# Usage:
#   ::gec::init   - Initialize GEC (loads models)
#   ::gec::process $text - Process text through GEC pipeline
#   ::gec::shutdown - Clean up resources

namespace eval ::gec {
    variable initialized 0
    variable enabled 1
    variable ready 0
    variable script_dir
    variable log_file ""
    variable log_enabled 1
}

# Capture script directory at load time (before procs are called)
# Falls back to src/ under current directory if [info script] is empty
if {[info script] ne ""} {
    set ::gec::script_dir [file dirname [file normalize [info script]]]
} else {
    set ::gec::script_dir [file normalize [file join [pwd] src]]
}

# Initialize the GEC system
proc ::gec::init {} {
    variable initialized
    variable ready
    variable script_dir

    if {$initialized} {
        return 1
    }

    # Find the GEC module directory
    set gec_dir [file normalize [file join $script_dir gec]]

    # Add required paths
    lappend ::auto_path [file join $gec_dir lib]
    lappend ::auto_path [file normalize [file join $gec_dir ../wordpiece/lib]]

    # Find model files
    set models_dir [file normalize [file join $script_dir ../models/gec]]
    set data_dir [file normalize [file join $script_dir ../data]]

    set punctcap_model [file join $models_dir distilbert-punct-cap.onnx]
    set homophone_model [file join $models_dir electra-small-generator.onnx]
    set grammar_model [file join $models_dir t5-grammar-ct2]
    set vocab_path [file join $gec_dir vocab.txt]
    set homophones_path [file join $data_dir homophones.json]

    # Verify files exist (grammar model is optional)
    foreach {name path} [list \
        "Punctcap model" $punctcap_model \
        "Homophone model" $homophone_model \
        "Vocab" $vocab_path \
        "Homophones" $homophones_path] {
        if {![file exists $path]} {
            puts stderr "GEC: Missing $name at $path"
            return 0
        }
    }

    # Check if grammar model exists (optional)
    if {![file isdirectory $grammar_model]} {
        puts stderr "GEC: Grammar model not found at $grammar_model (Stage 3 disabled)"
        set grammar_model ""
    }

    # Load pipeline and gec package for device detection
    source [file join $gec_dir pipeline.tcl]
    package require gec

    # Check available devices (like tests do)
    set available_devices [gec::devices]
    set use_device "CPU"
    if {"NPU" in $available_devices} {
        set use_device "NPU"
    }

    # Initialize on selected device
    if {[catch {
        gec_pipeline::init \
            -punctcap_model $punctcap_model \
            -homophone_model $homophone_model \
            -grammar_model $grammar_model \
            -vocab $vocab_path \
            -homophones $homophones_path \
            -device $use_device
        puts stderr "GEC: Initialized on $use_device"
    } err]} {
        # If NPU failed, try CPU as fallback
        if {$use_device eq "NPU"} {
            puts stderr "GEC: $use_device init failed: $err"
            puts stderr "GEC: Trying CPU..."
            if {[catch {
                gec_pipeline::init \
                    -punctcap_model $punctcap_model \
                    -homophone_model $homophone_model \
                    -grammar_model $grammar_model \
                    -vocab $vocab_path \
                    -homophones $homophones_path \
                    -device CPU
                puts stderr "GEC: Initialized on CPU"
            } err2]} {
                puts stderr "GEC: Failed to initialize: $err2"
                return 0
            }
        } else {
            puts stderr "GEC: Failed to initialize: $err"
            return 0
        }
    }

    set initialized 1
    set ready 1

    # Initialize log file
    variable log_file
    set log_file [file join $::env(HOME) .talkie-gec.log]

    return 1
}

# Write to GEC log file
proc ::gec::log {input output} {
    variable log_file
    variable log_enabled

    if {!$log_enabled || $log_file eq ""} return

    set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    set entry "$timestamp | \"$input\" -> \"$output\""

    if {[catch {
        set fd [open $log_file a]
        puts $fd $entry
        close $fd
    } err]} {
        puts stderr "GEC log error: $err"
    }
}

# Process text through GEC pipeline
proc ::gec::process {text} {
    variable initialized
    variable enabled
    variable ready

    if {!$initialized || !$enabled || !$ready} {
        return $text
    }

    if {[catch {
        set result [gec_pipeline::process $text]
    } err]} {
        puts stderr "GEC error: $err"
        return $text
    }

    if {$result ne $text} {
        puts stderr "GEC: '$text' -> '$result'"
        log $text $result
    }

    return $result
}

# Get statistics
proc ::gec::stats {} {
    variable initialized
    if {!$initialized} {
        return {}
    }
    return [gec_pipeline::stats]
}

# Get timing from last process call
proc ::gec::last_timing {} {
    variable initialized
    if {!$initialized} {
        return {homo_ms 0 punct_ms 0 grammar_ms 0 total_ms 0}
    }
    return [gec_pipeline::last_timing]
}

# Enable/disable GEC and logging
proc ::gec::configure {args} {
    variable enabled
    variable log_enabled
    foreach {opt val} $args {
        switch -- $opt {
            -enabled { set enabled $val }
            -log { set log_enabled $val }
            default { error "Unknown option: $opt" }
        }
    }
}

# Get log file path
proc ::gec::log_path {} {
    variable log_file
    return $log_file
}

# Clear the log file
proc ::gec::log_clear {} {
    variable log_file
    if {$log_file ne "" && [file exists $log_file]} {
        file delete $log_file
    }
}

# Clean up resources
proc ::gec::shutdown {} {
    variable initialized
    variable ready

    if {$initialized} {
        catch { gec_pipeline::cleanup }
        set initialized 0
        set ready 0
    }
}
