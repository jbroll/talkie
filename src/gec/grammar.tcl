# grammar.tcl - T5 grammar correction using CTranslate2
#
# Stage 3 of GEC pipeline: fixes subject-verb agreement, tense, articles, contractions
# Uses T5-efficient-tiny model via CTranslate2 for fast CPU inference
#
# NOTE: Disabled by default due to T5 hallucination issues (e.g., "tcl" -> "till").
# Consider GECToR (tag-based) as an alternative that cannot hallucinate.
#
# Usage:
#   grammar::init -model PATH
#   set corrected [grammar::correct $text]
#   grammar::cleanup

package require ct2

namespace eval grammar {
    variable model ""
    variable initialized 0
    variable enabled 1
}

# Initialize grammar correction
proc grammar::init {args} {
    variable model
    variable initialized

    # Parse arguments
    set model_path ""

    foreach {opt val} $args {
        switch -- $opt {
            -model { set model_path $val }
            default { error "Unknown option: $opt" }
        }
    }

    if {$model_path eq ""} {
        error "Missing required -model option"
    }

    # Load CTranslate2 model
    set model [ct2::load_model -path $model_path]

    set initialized 1
    puts stderr "grammar: loaded T5 model from $model_path"
    return 1
}

# Correct grammar in text
proc grammar::correct {text} {
    variable model
    variable initialized
    variable enabled

    if {!$initialized} {
        error "grammar::init must be called first"
    }

    if {!$enabled || $text eq ""} {
        return $text
    }

    return [$model correct $text]
}

# Enable/disable grammar correction
proc grammar::configure {args} {
    variable enabled

    foreach {opt val} $args {
        switch -- $opt {
            -enabled { set enabled $val }
            default { error "Unknown option: $opt" }
        }
    }
}

# Clean up resources
proc grammar::cleanup {} {
    variable model
    variable initialized

    if {$initialized} {
        catch { $model close }
        set model ""
        set initialized 0
    }
}

package provide grammar 1.0
