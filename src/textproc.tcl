package require jbr::pipe
interp alias {} | {} pipe

set ::textproc_capitalize_next 1  ;# Only true at start or after sentence endings
set ::textproc_prefix ""          ;# Empty at start, " " for subsequent utterances
set ::textproc_macros {}          ;# List of {pattern replacement} pairs

proc textproc_load_map {} {
    set map_file [file join [file dirname [info script]] .. talkie.map]
    set raw [| { cat $map_file | regsub -all -line {#.*$} ~ "" }]

    # Parse into list of {pattern replacement end_only} tuples
    # Patterns ending with $ only match at end of utterance
    set ::textproc_macros {}
    foreach {pattern replacement} $raw {
        set pattern [string trim $pattern]
        set replacement [string trim $replacement " \t"]  ;# Trim spaces/tabs only, keep newlines
        if {$pattern eq "" || $pattern eq $replacement} continue

        # Check for end-of-utterance marker
        set end_only 0
        if {[string index $pattern end] eq "\$"} {
            set pattern [string range $pattern 0 end-1]
            set end_only 1
        }

        lappend ::textproc_macros [list $pattern $replacement $end_only]
    }
}

# Apply macros with word boundary matching
# Patterns ending with $ only match at end of utterance
proc textproc_apply_macros {words} {
    set result {}
    set i 0
    set n [llength $words]

    while {$i < $n} {
        set matched 0

        # Try to match macros (longest first would be better, but check all)
        foreach macro $::textproc_macros {
            lassign $macro pattern replacement end_only
            set pattern_words [split $pattern]
            set pattern_len [llength $pattern_words]

            # Check if we have enough words left
            if {$i + $pattern_len <= $n} {
                # If end_only, must be at end of utterance
                set at_end [expr {$i + $pattern_len == $n}]
                if {$end_only && !$at_end} {
                    continue
                }

                set candidate [lrange $words $i [expr {$i + $pattern_len - 1}]]
                if {[string tolower [join $candidate]] eq [string tolower $pattern]} {
                    # Match found - apply replacement
                    lappend result $replacement
                    incr i $pattern_len
                    set matched 1
                    break
                }
            }
        }

        if {!$matched} {
            lappend result [lindex $words $i]
            incr i
        }
    }

    return $result
}

proc textproc {text} {
    if {$text eq ""} { return "" }

    # Split into words and apply macros with word boundary matching
    set words [split $text]
    set words [textproc_apply_macros $words]

    set result $::textproc_prefix
    foreach word $words {
        # Check if this is punctuation (attaches without leading space)
        if {[regexp {^[.!?,:;\-]+$} $word] || $word eq "\n" || $word eq "\n\n"} {
            # Hyphen attaches to both sides (no trailing space either)
            if {$word eq "-"} {
                set result "[string trimright $result]$word"
            } else {
                set result "$result$word"
            }
            if {$word eq "." || $word eq "!" || $word eq "?"} {
                set ::textproc_capitalize_next 1
            }
        } else {
            if {$result ne $::textproc_prefix && ![string match "*-" $result]} {
                set result "$result "
            }
            if {$::textproc_capitalize_next} {
                set word [string totitle $word]
                set ::textproc_capitalize_next 0
            }
            set result "$result$word"
        }
    }

    set ::textproc_prefix " "

    return $result
}

proc textproc_reset {} {
    set ::textproc_capitalize_next 1
    set ::textproc_prefix ""
}

proc textproc_init {} {
    textproc_load_map
    textproc_reset
}

# Initialize on load
textproc_init
