# punctcap.tcl - Punctuation and Capitalization restoration using DistilBERT
#
# Uses token classification to predict punctuation and capitalization
# for each word in lowercase, unpunctuated text from speech recognition.

package require gec
package require wordpiece

namespace eval punctcap {
    # Model state
    variable model ""
    variable request ""
    variable initialized 0

    # Class mappings (empirically determined from model output)
    # Format: class_id -> {capitalization punctuation}
    # Capitalization: O=lowercase, U=UPPERCASE, F=First-cap
    # Punctuation: "" (none), "." (period), "," (comma), "?" (question), "!" (exclaim)
    variable class_map
    array set class_map {
        0  {U ""}
        1  {F ""}
        2  {O ""}
        3  {U ""}
        4  {F "."}
        5  {F "."}
        6  {O "."}
        7  {F ","}
        8  {O ","}
        9  {U ","}
        10 {O ""}
        11 {F ""}
        12 {O "."}
        13 {F "?"}
        14 {O "?"}
        15 {U "?"}
        16 {F "!"}
        17 {O "!"}
        18 {U "!"}
        19 {F ":"}
        20 {O ":"}
        21 {U ":"}
        22 {O ""}
        23 {O ""}
    }
}

# Initialize the punctuation/capitalization system
proc punctcap::init {args} {
    variable model
    variable request
    variable initialized

    # Parse arguments
    set model_path ""
    set vocab_path ""
    set device "NPU"

    foreach {opt val} $args {
        switch -- $opt {
            -model { set model_path $val }
            -vocab { set vocab_path $val }
            -device { set device $val }
            default { error "Unknown option: $opt" }
        }
    }

    if {$model_path eq ""} {
        error "Missing required -model option"
    }
    if {$vocab_path eq ""} {
        error "Missing required -vocab option"
    }

    # Load vocabulary
    wordpiece::load $vocab_path

    # Load DistilBERT model
    set model [gec::load_model -path $model_path -device $device]
    set request [$model create_request]

    set initialized 1
    return 1
}

# Clean up resources
proc punctcap::cleanup {} {
    variable model
    variable request
    variable initialized

    if {$initialized} {
        catch { $request close }
        catch { $model close }
        set initialized 0
    }
}

# Apply capitalization to a word
proc punctcap::apply_cap {word cap_type} {
    switch $cap_type {
        O { return [string tolower $word] }
        U { return [string toupper $word] }
        F { return [string totitle $word] }
        default { return $word }
    }
}

# Restore punctuation and capitalization
proc punctcap::restore {text} {
    variable request
    variable initialized
    variable class_map

    if {!$initialized} {
        error "punctcap::init must be called first"
    }

    # Tokenize the text
    set tokens [wordpiece::encode $text 64]
    set mask [wordpiece::attention_mask $tokens]

    # Run inference
    $request set_input 0 $tokens
    $request set_input 1 $mask
    $request infer

    # Get output
    set output [$request get_output 0]
    set data [dict get $output data]

    # Process each token
    set result_words {}
    set prev_punct ""

    for {set pos 1} {$pos < 64} {incr pos} {
        set tid [lindex $tokens $pos]

        # Skip padding and special tokens
        if {$tid == 0 || $tid == 102} break
        if {$tid == 101} continue  ;# Skip [CLS]

        # Get the token string
        set token_str [wordpiece::id_to_token $tid]

        # Find best class for this position
        set start [expr {$pos * 24}]
        set best_class 0
        set best_score -1e30
        for {set c 0} {$c < 24} {incr c} {
            set score [lindex $data [expr {$start + $c}]]
            if {$score > $best_score} {
                set best_score $score
                set best_class $c
            }
        }

        # Get capitalization and punctuation from class
        if {[info exists class_map($best_class)]} {
            lassign $class_map($best_class) cap_type punct
        } else {
            set cap_type O
            set punct ""
        }

        # Handle subword tokens (##prefix)
        if {[string match "##*" $token_str]} {
            # Subword - append to previous word without space
            set token_str [string range $token_str 2 end]
            if {[llength $result_words] > 0} {
                set last_idx [expr {[llength $result_words] - 1}]
                set last_word [lindex $result_words $last_idx]
                # Remove trailing punct from previous word temporarily
                set last_word_clean [string trimright $last_word ".,?!:;"]
                set prev_trailing [string range $last_word [string length $last_word_clean] end]
                set result_words [lreplace $result_words $last_idx $last_idx "${last_word_clean}${token_str}${prev_trailing}"]
                continue
            }
        }

        # Apply capitalization
        set word [apply_cap $token_str $cap_type]

        # Add punctuation
        if {$punct ne ""} {
            append word $punct
        }

        lappend result_words $word
    }

    return [join $result_words " "]
}

# Restore with detailed results
proc punctcap::restore_verbose {text} {
    variable request
    variable initialized
    variable class_map

    if {!$initialized} {
        error "punctcap::init must be called first"
    }

    set tokens [wordpiece::encode $text 64]
    set mask [wordpiece::attention_mask $tokens]

    $request set_input 0 $tokens
    $request set_input 1 $mask
    $request infer

    set output [$request get_output 0]
    set data [dict get $output data]

    set results {}

    for {set pos 1} {$pos < 64} {incr pos} {
        set tid [lindex $tokens $pos]
        if {$tid == 0 || $tid == 102} break
        if {$tid == 101} continue

        set token_str [wordpiece::id_to_token $tid]

        set start [expr {$pos * 24}]
        set best_class 0
        set best_score -1e30
        for {set c 0} {$c < 24} {incr c} {
            set score [lindex $data [expr {$start + $c}]]
            if {$score > $best_score} {
                set best_score $score
                set best_class $c
            }
        }

        if {[info exists class_map($best_class)]} {
            lassign $class_map($best_class) cap_type punct
        } else {
            set cap_type O
            set punct ""
        }

        lappend results [dict create \
            position $pos \
            token $token_str \
            class $best_class \
            capitalization $cap_type \
            punctuation $punct \
            output [apply_cap $token_str $cap_type]$punct]
    }

    return $results
}

# Package export
package provide punctcap 1.0
