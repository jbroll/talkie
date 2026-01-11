# POS-based homophone disambiguation wrapper
#
# Calls Python module for POS tagging and homophone disambiguation

namespace eval ::pos {
    variable enabled 1
    variable dic_path ""
    variable vocab_path ""
    variable arpa_path ""
    variable disambiguator_ready 0

    proc init {dic vocab {arpa ""}} {
        variable dic_path
        variable vocab_path
        variable arpa_path
        variable disambiguator_ready

        set dic_path $dic
        set vocab_path $vocab
        set arpa_path $arpa

        # Pre-initialize the disambiguator in background
        puts stderr "POS: initializing with dic=$dic vocab=$vocab arpa=$arpa"

        # Check files exist
        if {![file exists $dic]} {
            puts stderr "POS: dictionary not found: $dic"
            return
        }
        if {![file exists $vocab]} {
            puts stderr "POS: vocabulary not found: $vocab"
            return
        }
        if {$arpa ne "" && ![file exists $arpa]} {
            puts stderr "POS: ARPA file not found: $arpa"
            return
        }

        set disambiguator_ready 1
    }

    proc disambiguate {text} {
        variable enabled
        variable dic_path
        variable vocab_path
        variable arpa_path
        variable disambiguator_ready

        if {!$enabled || !$disambiguator_ready || $text eq ""} {
            return $text
        }

        # Call Python module
        set script_dir [file dirname [info script]]
        set py_script [file join $script_dir pos_disambiguate.py]

        if {![file exists $py_script]} {
            puts stderr "POS: script not found: $py_script"
            return $text
        }

        # Build arpa argument if provided
        set arpa_arg ""
        if {$arpa_path ne ""} {
            set arpa_arg ", arpa_path='$arpa_path'"
        }

        try {
            # Pass text via stdin, get result from stdout
            set cmd [list python3 -c "
import sys
sys.path.insert(0, '$script_dir')
from pos_disambiguate import HomophoneDisambiguator
d = HomophoneDisambiguator('$dic_path', '$vocab_path'$arpa_arg)
text = sys.stdin.read().strip()
result = d.disambiguate(text, debug=True)
print(result)
"]
            set result [exec {*}$cmd << $text 2>@stderr]
            return [string trim $result]
        } on error {err} {
            puts stderr "POS error: $err"
            return $text
        }
    }
}
