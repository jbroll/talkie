package require jbr::pipe
interp alias {} | {} pipe

set ::textproc_capitalize_next 1
set ::textproc_prefix ""
set ::textproc_macros {}

proc textproc_load_map {} {
    set map_file [file join [file dirname [info script]] .. talkie.map]
    set raw [| { cat $map_file | regsub -all -line {#.*$} ~ "" }]

    # Parse {pattern replacement} pairs into {pattern_words replacement end_only} tuples
    set ::textproc_macros {}
    foreach {pattern replacement} $raw {
        set pattern [string trim $pattern]
        set replacement [string trim $replacement " \t"]
        if {$pattern eq "" || $pattern eq $replacement} continue

        set end_only [string equal [string index $pattern end] "\$"]
        if {$end_only} { set pattern [string range $pattern 0 end-1] }

        lappend ::textproc_macros [list [split $pattern] $replacement $end_only]
    }
}

proc textproc_apply_macros {words} {
    set result {}
    set i 0
    set n [llength $words]

    while {$i < $n} {
        set matched 0
        foreach macro $::textproc_macros {
            lassign $macro pattern_words replacement end_only
            set plen [llength $pattern_words]

            if {$i + $plen > $n} continue
            if {$end_only && $i + $plen != $n} continue

            set candidate [lrange $words $i [expr {$i + $plen - 1}]]
            if {[string tolower [join $candidate]] eq [string tolower [join $pattern_words]]} {
                lappend result $replacement
                incr i $plen
                set matched 1
                break
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

    set words [textproc_apply_macros [split $text]]
    set result $::textproc_prefix

    foreach word $words {
        set is_punct [regexp {^[.!?,:;\-\n]+$} $word]

        if {$is_punct} {
            # Hyphen attaches to both sides; other punctuation just appends
            if {$word eq "-"} { set result [string trimright $result] }
            append result $word
            if {$word in {. ! ?}} { set ::textproc_capitalize_next 1 }
        } else {
            # Add space before words (unless after prefix or hyphen)
            if {$result ne $::textproc_prefix && ![string match "*-" $result]} {
                append result " "
            }
            if {$::textproc_capitalize_next} {
                set word [string totitle $word]
                set ::textproc_capitalize_next 0
            }
            append result $word
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
