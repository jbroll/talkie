package require jbr::pipe
interp alias {} | {} pipe

set ::textproc_capitalize_next 1  ;# Only true at start or after sentence endings
set ::textproc_prefix ""          ;# Empty at start, " " for subsequent utterances
set ::textproc_map {}             ;# Punctuation mapping loaded from file

proc textproc_load_map {} {
    set map_file [file join [file dirname [info script]] .. talkie.map]
    set ::textproc_map [| { cat $map_file | regsub -all -line {#.*$} ~ "" }]
    # puts $::textproc_map
}

proc textproc {text} {
    if {$text eq ""} { return "" }

    set text [string map $::textproc_map $text]

    set result $::textproc_prefix
    foreach word [split $text] {
        if {[string match {[.!?,:;-]} $word]} {
            set result "$result$word"
            if {$word eq "." || $word eq "!" || $word eq "?"} {
                set ::textproc_capitalize_next 1
            }
        } else {
            if {$result ne $::textproc_prefix} { set result "$result " }
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
