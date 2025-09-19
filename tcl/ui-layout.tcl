#!/usr/bin/env tclsh
#
package require Tk
package require jbr::layout
package require jbr::layoutoption
package require jbr::layoutdialog
package require jbr::layoutoptmenu

proc bgerror { args } {
    print {*}$args
}

# UI to App interface is composed of these global variables
#
#

# ::partial is the variable containing name of the partial result text widget
# ::final   is the variable containing name of the final result text widget
#
# proc quit is expected to clean up and exit the app.
#
# The app supplies a list of string names for the available input devices for
# the user to select from in the global ::input_devices
#
# The app supplies a list of string root file names for the available model
# files for the user to select from in the global ::model_files.  Model files
# should be found in $script_dir/../models/vosk.
#
# Transcription state and user feedback.  The App should trace ::transcriptoin to
# monitor state and set ::audiolevel and ::confidence to provide user feedback.
 
set transcribing 0
set audiolevel   0
set confidence   0

# The global configuration array with the defaults
#
array set ::config {
    input_device              pulse
    confidence_threshold      175
    lookback_seconds          1.0
    silence_seconds            .5
    vosk_beam                 20
    vosk_lattice              8
    vosk_alternatives         1
    vosk_modelfile            vosk-model-en-us-0.22-lgraph
    noise_floor_percentile    10
    speech_floor_percentile   70
    audio_threshold_multiplier 2.5
    speech_min_multiplier     0.8
    speech_max_multiplier     1.5
    max_confidence_penalty    100
}

# UI initializaiton and callbacks -----------------------------------

proc audiolevel { value } { return [format "Audio: %7.2f" $value] }
proc confidence { value } { return [format "Conf: %7.0f" $value] }

set TranscribingStateLabel { Idle Transcribing }
set TranscribingStateColor { pink lightgreen }
set TranscribingButtonLabel { Start "Stop " }

set AudioRanges { { 0    15        50         75 } 
                  { pink lightblue lightgreen #40C040 } }

proc toggle { x } {
    set $x [expr { ![set $x] }]
}
grid [row .w -sticky news {
    # Global options
    #
    -sticky news
    -label.pady 12

    @ Transcribing -text :transcribing@TranscribingStateLabel  -bg :transcribing@TranscribingStateColor -width 15
    ! Start        -text :transcribing@TranscribingButtonLabel -command "toggle ::transcribing"         -width 15
    @ "" -width 5
    @ Audio: -text :audiolevel!audiolevel -bg :audiolevel&AudioRanges   -width 13
    @ Conf:  -text :confidence!confidence                               -width 13
    @ "" -width 5
    ! Config -command config 
    ! Quit -command quit                                &
    text ::final   -width 60 -height 10 - - - - - - -   &
    text ::partial -width 60 -height  2 - - - - - - -  
 }] -sticky news

proc config {} {
    layout-dialog-show .dlg "Talkie Configuration" {
        -label.pady 6
        -scale.length 200
        -scale.showvalue false
        -scale.orient horizontal
        -scale.width 20

        @ "Input Device" x                                ? config(input_device) -listvariable input_devices         &
        @ "Confidence"   @ :config(confidence_threshold) -width 10 <--> config(confidence_threshold) -from 0 -to 200 &
        @ "Lookback"     @ :config(lookback_seconds)     -width 10 <--> config(lookback_seconds)     -from 0 -to   3 -resolution 0.1 &
        @ "Silence"      @ :config(silence_seconds)      -width 10 <--> config(silence_seconds)      -from 0 -to   3 -resolution 0.1 &
        @ "Vosk Beam"    @ :config(vosk_beam)            -width 10 <--> config(vosk_beam)            -from 0 -to  50 &
        @ "Lattice Beam" @ :config(vosk_lattice)         -width 10 <--> config(vosk_lattice)         -from 0 -to  20 &
        @ "Alternatives" @ :config(vosk_alternatives)    -width 10 <--> config(vosk_alternatives)    -from 1 -to   3 &
        @ "Model"        x                               ? config(vosk_modelfile) -listvariable model_files              &
        @ ""             -                                                                                               &
        @ "Noise Floor Percentile"     @ :config(noise_floor_percentile)    -width 10 <--> config(noise_floor_percentile)    -from 5 -to 25 &
        @ "Audio Threshold Multiplier" @ :config(audio_threshold_multiplier) -width 10 <--> config(audio_threshold_multiplier) -from 1.5 -to 5.0 -resolution 0.1 &
        @ "Speech Min Multiplier"      @ :config(speech_min_multiplier)     -width 10 <--> config(speech_min_multiplier)     -from 0.0 -to 1.0 -resolution 0.1 &
        @ "Speech Max Multiplier"      @ :config(speech_max_multiplier)     -width 10 <--> config(speech_max_multiplier)     -from 1.0 -to 2.0 -resolution 0.1 &
        @ "Max Confidence Penalty"     @ :config(max_confidence_penalty)    -width 10 <--> config(max_confidence_penalty)    -from 0 -to 200
    }
}

# Apply window positioning after UI is created
#
after idle {
    if {[info exists ::config(window_x)] && [info exists ::config(window_y)]} {
        wm geometry . "+$::config(window_x)+$::config(window_y)"
    }

    # Set up window position tracking
    bind . <Configure> {
        if {"%W" eq "."} {
            set geom [wm geometry .]
            if {[regexp {^\d+x\d+\+(-?\d+)\+(-?\d+)$} $geom -> x y]} {
                set ::config(window_x) $x
                set ::config(window_y) $y
            }
        }
    }
}
