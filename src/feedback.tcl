# feedback.tcl - Unified feedback logging for STT correction learning
#
# Logs three event types to ~/.config/talkie/feedback.jsonl:
#   gec    - GEC corrections (vosk output -> GEC output)
#   inject - Text injected via uinput
#   submit - Final text user submitted (from Claude hook)
#
# Usage:
#   ::feedback::init              - Initialize (call at startup)
#   ::feedback::gec $in $out      - Log GEC correction
#   ::feedback::inject $text      - Log uinput injection
#   ::feedback::submit $text $sid - Log user submission (from hook)

package require json::write

namespace eval ::feedback {
    variable log_file ""
    variable enabled 1
}

proc ::feedback::init {} {
    variable log_file
    variable enabled

    set log_dir [file join $::env(HOME) .config talkie]
    file mkdir $log_dir
    set log_file [file join $log_dir feedback.jsonl]
    set enabled 1
}

proc ::feedback::log {type args} {
    variable log_file
    variable enabled

    if {!$enabled || $log_file eq ""} return

    # Build entry with timestamp and type
    set entry [dict create \
        ts [clock milliseconds] \
        type $type]

    # Add type-specific fields
    foreach {k v} $args {
        dict set entry $k $v
    }

    # Write as JSON line
    if {[catch {
        set fd [open $log_file a]
        puts $fd [_to_json $entry]
        close $fd
    } err]} {
        puts stderr "Feedback log error: $err"
    }
}

proc ::feedback::_to_json {d} {
    set pairs {}
    dict for {k v} $d {
        set jk [json::write string $k]
        if {[string is wideinteger -strict $v]} {
            lappend pairs "$jk:$v"
        } elseif {[string is double -strict $v] && [string first . $v] >= 0} {
            lappend pairs "$jk:$v"
        } elseif {$v eq "true" || $v eq "false"} {
            lappend pairs "$jk:$v"
        } else {
            lappend pairs "$jk:[json::write string $v]"
        }
    }
    return "\{[join $pairs ,]\}"
}

# Log GEC correction
proc ::feedback::gec {input output} {
    log gec input $input output $output
}

# Log text injection
proc ::feedback::inject {text} {
    log inject text $text
}

# Log user submission (from Claude hook)
proc ::feedback::submit {text {session_id ""}} {
    if {$session_id ne ""} {
        log submit text $text session_id $session_id
    } else {
        log submit text $text
    }
}

proc ::feedback::configure {args} {
    variable enabled
    foreach {opt val} $args {
        switch -- $opt {
            -enabled { set enabled $val }
            default { error "Unknown option: $opt" }
        }
    }
}

proc ::feedback::path {} {
    variable log_file
    return $log_file
}

proc ::feedback::clear {} {
    variable log_file
    if {$log_file ne "" && [file exists $log_file]} {
        file delete $log_file
    }
}
