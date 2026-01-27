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
set buffer_health 0
set buffer_overflows 0

# Available speech engines (global list for config dialog)
set ::speech_engines {vosk sherpa faster-whisper}

# The global configuration array with the defaults
#
array set ::config {
    speech_engine             vosk
    input_device              default
    confidence_threshold      100
    lookback_seconds          0.5
    silence_seconds           0.3
    min_duration              0.30
    audio_threshold           25.0
    speech_min_multiplier     0.6
    speech_max_multiplier     1.3
    max_confidence_penalty    75
    typing_delay_ms           5
    vosk_beam                 10
    vosk_lattice              5
    vosk_modelfile            vosk-model-en-us-0.22-lgraph
    sherpa_max_active_paths   4
    sherpa_modelfile          sherpa-onnx-streaming-zipformer-en-2023-06-26
    faster_whisper_modelfile  ""
    gec_homophone             1
    gec_punctcap              1
    gec_grammar               0
}

# UI initializaiton and callbacks -----------------------------------

proc audiolevel { value } { return [format "Audio: %7.2f" $value] }
proc threshold_label { value } { return [format "Thr: %5.2f" $value] }
proc health_label { value } {
    upvar ::buffer_overflows overflows
    if {$value == 0} { return "OK" }
    if {$value == 1} { return "Warn:$overflows" }
    return "DROP:$overflows"
}

# Health status colors: 0=good (green), 1=warning (yellow), 2=critical (red)
set HealthColors { { 0 1 2 } { lightgreen yellow #FF6B6B } }

set TranscribingStateLabel { Idle Transcribing }
set TranscribingStateColor { pink lightgreen }
set TranscribingButtonLabel { Start "Stop " }

# Speech detection indicator
set is_speech 0
set SpeechStatusColor { lightblue #40C040 }

# Initialize threshold global
set ::audio_threshold 25.0

# AudioRanges: below threshold (pink), near threshold (lightblue), above threshold (green)
set AudioRanges { { 0 25.0 50.0 100.0 }
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
    ! Start        -text :transcribing@TranscribingButtonLabel -command "if {\$::transcribing} { audio::stop_transcription } else { audio::start_transcription }"         -width 15
    @ Thr: -text :audio_threshold!threshold_label -bg :is_speech@SpeechStatusColor -width 10
    @ Audio: -text :audiolevel!audiolevel -bg :audiolevel&AudioRanges   -width 13
    @ Buf:   -text :buffer_health!health_label -bg :buffer_health&HealthColors -width 13
    @ "" -width 5
    ! Config -command config
    ! Quit -command quit                              &
    text ::final   -width 60 -height 10 - - - - - - - &
    text ::partial -width 60 -height  2 - - - - - - -
 }] -sticky news

# Build config dialog spec based on current engine
proc build_config_spec {} {
    set config_spec [list \
        -label.pady 6 \
        -scale.length 200 \
        -scale.showvalue false \
        -scale.orient horizontal \
        -scale.width 20 \
    ]

    # Engine selection (hot-swap)
    lappend config_spec @ "Speech Engine" x ? config(speech_engine) -listvariable speech_engines &
    lappend config_spec @ "" - &

    # Common options
    lappend config_spec @ "Input Device" x ? config(input_device) -listvariable input_devices &
    lappend config_spec @ "Confidence" @ :config(confidence_threshold) -width 10 <--> config(confidence_threshold) -from 0 -to 200 &
    lappend config_spec @ "Lookback" @ :config(lookback_seconds) -width 10 <--> config(lookback_seconds) -from 0 -to 3 -resolution 0.1 &
    lappend config_spec @ "Silence" @ :config(silence_seconds) -width 10 <--> config(silence_seconds) -from 0 -to 3 -resolution 0.1 &
    lappend config_spec @ "Min Duration" @ :config(min_duration) -width 10 <--> config(min_duration) -from 0 -to 1 -resolution 0.01 &
    lappend config_spec @ "Typing Delay (ms)" @ :config(typing_delay_ms) -width 10 <--> config(typing_delay_ms) -from 0 -to 100 &
    lappend config_spec @ "" - &

    # Engine-specific options
    if {$::config(speech_engine) eq "vosk"} {
        lappend config_spec @ "Vosk Beam" @ :config(vosk_beam) -width 10 <--> config(vosk_beam) -from 0 -to 50 &
        lappend config_spec @ "Lattice Beam" @ :config(vosk_lattice) -width 10 <--> config(vosk_lattice) -from 0 -to 20 &
        lappend config_spec @ "Model" x ? config(vosk_modelfile) -listvariable vosk_model_files &
    } elseif {$::config(speech_engine) eq "sherpa"} {
        lappend config_spec @ "Max Active Paths" @ :config(sherpa_max_active_paths) -width 10 <--> config(sherpa_max_active_paths) -from 1 -to 10 &
        lappend config_spec @ "Model" x ? config(sherpa_modelfile) -listvariable sherpa_model_files &
    } elseif {$::config(speech_engine) eq "faster-whisper"} {
        lappend config_spec @ "Model" @ :config(faster_whisper_modelfile) -width 20 &
    }

    lappend config_spec @ "" - &

    # Threshold options
    lappend config_spec @ "Audio Threshold" @ :config(audio_threshold) -width 10 <--> config(audio_threshold) -from 1.0 -to 100.0 -resolution 1.0 &
    lappend config_spec @ "Speech Min Multiplier" @ :config(speech_min_multiplier) -width 10 <--> config(speech_min_multiplier) -from 0.0 -to 1.0 -resolution 0.1 &
    lappend config_spec @ "Speech Max Multiplier" @ :config(speech_max_multiplier) -width 10 <--> config(speech_max_multiplier) -from 1.0 -to 2.0 -resolution 0.1 &
    lappend config_spec @ "Max Confidence Penalty" @ :config(max_confidence_penalty) -width 10 <--> config(max_confidence_penalty) -from 0 -to 200

    # GEC (Grammar Error Correction) options
    lappend config_spec @ "" - &
    lappend config_spec @ "GEC Stages" ~ "Homophones" -variable config(gec_homophone) ~ "Punct/Caps" -variable config(gec_punctcap) ~ "Grammar" -variable config(gec_grammar)

    return $config_spec
}

# Rebuild config dialog when engine changes (if dialog is open)
proc config_dialog_refresh {args} {
    if {[winfo exists .dlg]} {
        # Dialog is open, rebuild it with engine-specific controls
        # Wait for engine swap to complete (100ms for audio stop + engine init)
        after 200 {
            if {[winfo exists .dlg]} {
                destroy .dlg
                config
            }
        }
    }
}

proc config {} {
    # Set up trace to rebuild dialog when engine changes
    if {![info exists ::config_dialog_trace_set]} {
        trace add variable ::config(speech_engine) write config_dialog_refresh
        set ::config_dialog_trace_set 1
    }

    set config_spec [build_config_spec]
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
