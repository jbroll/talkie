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
}

# Initialize the GEC system
proc ::gec::init {} {
    variable initialized
    variable ready

    if {$initialized} {
        return 1
    }

    # Find the GEC module directory
    set gec_dir [file normalize [file join [file dirname [info script]] gec]]

    # Add required paths
    lappend ::auto_path [file join $gec_dir lib]
    lappend ::auto_path [file normalize [file join $gec_dir ../wordpiece/lib]]

    # Find model files
    set models_dir [file normalize [file join [file dirname [info script]] ../models/gec]]
    set data_dir [file normalize [file join [file dirname [info script]] ../data]]

    set punctcap_model [file join $models_dir distilbert-punct-cap.onnx]
    set homophone_model [file join $models_dir electra-small-generator.onnx]
    set vocab_path [file join $gec_dir vocab.txt]
    set homophones_path [file join $data_dir homophones.json]

    # Verify files exist
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

    # Load pipeline
    source [file join $gec_dir pipeline.tcl]

    # Try NPU first, fall back to CPU
    if {[catch {
        gec_pipeline::init \
            -punctcap_model $punctcap_model \
            -homophone_model $homophone_model \
            -vocab $vocab_path \
            -homophones $homophones_path \
            -device NPU
        puts stderr "GEC: Initialized on NPU"
    } err]} {
        puts stderr "GEC: NPU init failed: $err"
        puts stderr "GEC: Trying CPU..."
        if {[catch {
            gec_pipeline::init \
                -punctcap_model $punctcap_model \
                -homophone_model $homophone_model \
                -vocab $vocab_path \
                -homophones $homophones_path \
                -device CPU
            puts stderr "GEC: Initialized on CPU"
        } err2]} {
            puts stderr "GEC: Failed to initialize: $err2"
            return 0
        }
    }

    set initialized 1
    set ready 1
    return 1
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
        return {homo_ms 0 punct_ms 0 total_ms 0}
    }
    return [gec_pipeline::last_timing]
}

# Enable/disable GEC
proc ::gec::configure {args} {
    variable enabled
    foreach {opt val} $args {
        switch -- $opt {
            -enabled { set enabled $val }
            default { error "Unknown option: $opt" }
        }
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
