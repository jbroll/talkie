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

# Available speech engines (global list for config dialog)
set ::speech_engines {vosk sherpa}

# The global configuration array with the defaults
#
array set ::config {
    speech_engine             vosk
    input_device              pulse
    confidence_threshold      175
    lookback_seconds          1.0
    silence_seconds            .5
    minumum_duration           .25
    noise_floor_percentile    10
    speech_floor_percentile   70
    audio_threshold_multiplier 2.5
    speech_min_multiplier     0.8
    speech_max_multiplier     1.5
    max_confidence_penalty    100
    vosk_beam                 20
    vosk_lattice              8
    vosk_alternatives         1
    vosk_modelfile            vosk-model-en-us-0.22-lgraph
    sherpa_max_active_paths   4
    sherpa_modelfile          sherpa-onnx-streaming-zipformer-en-2023-06-26
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
    # Capture current engine before opening dialog
    set ::initial_engine $::config(speech_engine)

    # Build dynamic config based on selected engine
    set config_spec [list \
        -label.pady 6 \
        -scale.length 200 \
        -scale.showvalue false \
        -scale.orient horizontal \
        -scale.width 20 \
    ]

    # Engine selection (triggers restart prompt)
    lappend config_spec @ "Speech Engine" x ? config(speech_engine) -listvariable speech_engines &
    lappend config_spec @ "" - &

    # Common options
    lappend config_spec @ "Input Device" x ? config(input_device) -listvariable input_devices &
    lappend config_spec @ "Confidence" @ :config(confidence_threshold) -width 10 <--> config(confidence_threshold) -from 0 -to 200 &
    lappend config_spec @ "Lookback" @ :config(lookback_seconds) -width 10 <--> config(lookback_seconds) -from 0 -to 3 -resolution 0.1 &
    lappend config_spec @ "Silence" @ :config(silence_seconds) -width 10 <--> config(silence_seconds) -from 0 -to 3 -resolution 0.1 &
    lappend config_spec @ "Min Duration" @ :config(min_duration) -width 10 <--> config(min_duration) -from 0 -to 1 -resolution 0.01 &
    lappend config_spec @ "" - &

    # Engine-specific options
    if {$::config(speech_engine) eq "vosk"} {
        lappend config_spec @ "Vosk Beam" @ :config(vosk_beam) -width 10 <--> config(vosk_beam) -from 0 -to 50 &
        lappend config_spec @ "Lattice Beam" @ :config(vosk_lattice) -width 10 <--> config(vosk_lattice) -from 0 -to 20 &
        lappend config_spec @ "Alternatives" @ :config(vosk_alternatives) -width 10 <--> config(vosk_alternatives) -from 1 -to 3 &
        lappend config_spec @ "Model" x ? config(vosk_modelfile) -listvariable vosk_model_files &
    } elseif {$::config(speech_engine) eq "sherpa"} {
        lappend config_spec @ "Max Active Paths" @ :config(sherpa_max_active_paths) -width 10 <--> config(sherpa_max_active_paths) -from 1 -to 10 &
        lappend config_spec @ "Model" x ? config(sherpa_modelfile) -listvariable sherpa_model_files &
    }

    lappend config_spec @ "" - &

    # Threshold options
    lappend config_spec @ "Noise Floor Percentile" @ :config(noise_floor_percentile) -width 10 <--> config(noise_floor_percentile) -from 5 -to 25 &
    lappend config_spec @ "Audio Threshold Multiplier" @ :config(audio_threshold_multiplier) -width 10 <--> config(audio_threshold_multiplier) -from 1.5 -to 5.0 -resolution 0.1 &
    lappend config_spec @ "Speech Min Multiplier" @ :config(speech_min_multiplier) -width 10 <--> config(speech_min_multiplier) -from 0.0 -to 1.0 -resolution 0.1 &
    lappend config_spec @ "Speech Max Multiplier" @ :config(speech_max_multiplier) -width 10 <--> config(speech_max_multiplier) -from 1.0 -to 2.0 -resolution 0.1 &
    lappend config_spec @ "Max Confidence Penalty" @ :config(max_confidence_penalty) -width 10 <--> config(max_confidence_penalty) -from 0 -to 200

    layout-dialog-show .dlg "Talkie Configuration" $config_spec
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
