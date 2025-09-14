#!/usr/bin/env tclsh
# speech_transcription_example.tcl - Complete example of streaming speech transcription
# Demonstrates PortAudio + Vosk integration for real-time speech recognition

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]
set auto_path [linsert $auto_path 0 [file join [pwd] ../pa lib]]

# Load required packages
package require pa
package require vosk

# Configuration
set config {
    model_path "../../models/vosk-model-en-us-0.22-lgraph"
    sample_rate 16000
    channels 1
    frames_per_buffer 1024
    confidence_threshold 0.3
    max_alternatives 1
    device_filter "USB"
}

# Global state
set g_state {
    stream ""
    model ""
    recognizer ""
    audio_count 0
    speech_count 0
    partial_count 0
    final_count 0
    running 0
}

proc log {level message} {
    set timestamp [clock format [clock seconds] -format "%H:%M:%S"]
    puts "\[$timestamp\] $level: $message"
}

proc get_config {key} {
    global config
    return [dict get $config $key]
}

proc get_state {key} {
    global g_state
    return [dict get $g_state $key]
}

proc set_state {key value} {
    global g_state
    dict set g_state $key $value
}

# Initialize audio and speech systems
proc initialize_systems {} {
    log "INFO" "Initializing PortAudio and Vosk systems"

    # Initialize PortAudio
    if {[catch {Pa_Init} err]} {
        log "ERROR" "Failed to initialize PortAudio: $err"
        return 0
    }

    # Initialize Vosk
    if {[catch {Vosk_Init} err]} {
        log "ERROR" "Failed to initialize Vosk: $err"
        return 0
    }

    vosk::set_log_level -1  ;# Quiet mode
    log "INFO" "Both systems initialized successfully"
    return 1
}

# Load speech recognition model
proc load_speech_model {} {
    set model_path [get_config model_path]

    if {![file exists $model_path]} {
        log "ERROR" "Model not found at: $model_path"
        return ""
    }

    log "INFO" "Loading Vosk model (this may take a moment)..."
    if {[catch {vosk::load_model -path $model_path} model err]} {
        log "ERROR" "Failed to load model: $err"
        return ""
    }

    log "INFO" "Model loaded successfully: $model"
    return $model
}

# Create speech recognizer with callback
proc create_recognizer {model} {
    set sample_rate [get_config sample_rate]
    set confidence_threshold [get_config confidence_threshold]
    set max_alternatives [get_config max_alternatives]

    if {[catch {
        $model create_recognizer \
            -rate $sample_rate \
            -callback speech_recognition_callback \
            -confidence $confidence_threshold \
            -alternatives $max_alternatives
    } recognizer err]} {
        log "ERROR" "Failed to create recognizer: $err"
        return ""
    }

    log "INFO" "Recognizer created: $recognizer"
    return $recognizer
}

# Speech recognition callback - called when Vosk has results
proc speech_recognition_callback {recognizer json_result is_final} {
    set speech_count [get_state speech_count]
    incr speech_count
    set_state speech_count $speech_count

    if {$is_final} {
        set final_count [get_state final_count]
        incr final_count
        set_state final_count $final_count
        set prefix "FINAL"
    } else {
        set partial_count [get_state partial_count]
        incr partial_count
        set_state partial_count $partial_count
        set prefix "PARTIAL"
    }

    # Parse JSON to extract meaningful information
    set text ""
    set confidence ""

    if {$json_result ne ""} {
        # Extract text
        if {[regexp {"text"\s*:\s*"([^"]*)"} $json_result -> extracted_text]} {
            set text $extracted_text
        }

        # Extract confidence if available
        if {[regexp {"confidence"\s*:\s*([0-9.]+)} $json_result -> conf]} {
            set confidence " (conf: $conf)"
        }
    }

    # Only show non-empty results
    if {$text ne "" && [string trim $text] ne ""} {
        log "SPEECH" "$prefix$confidence: '$text'"

        # For final results, also show some statistics
        if {$is_final} {
            set audio_count [get_state audio_count]
            log "STATS" "Processed $audio_count audio buffers, $speech_count speech events"
        }
    }
}

# Audio callback - called by PortAudio with new audio data
proc audio_callback {stream timestamp data} {
    set audio_count [get_state audio_count]
    incr audio_count
    set_state audio_count $audio_count

    # Show periodic status (every 2 seconds worth of audio at typical frame rates)
    if {$audio_count % 100 == 0} {
        log "AUDIO" "Processed $audio_count audio buffers (timestamp: [format "%.2f" $timestamp]s)"
    }

    # Feed audio data to speech recognizer
    set recognizer [get_state recognizer]
    if {$recognizer ne ""} {
        if {[catch {$recognizer process $data} err]} {
            log "ERROR" "Speech processing failed: $err"
        }
    }
}

# Find best audio input device
proc find_audio_device {} {
    set device_filter [get_config device_filter]

    log "INFO" "Available audio devices:"
    set best_device "default"

    foreach device [pa::list_devices] {
        dict with device {
            log "INFO" "  Device $index: $name (inputs: $maxInputChannels, rate: $defaultSampleRate)"

            # Prefer devices with input channels that match our filter
            if {$maxInputChannels > 0} {
                if {$device_filter ne "" && [string match -nocase "*$device_filter*" $name]} {
                    set best_device $name
                    log "INFO" "  -> Selected device: $name"
                } elseif {$best_device eq "default"} {
                    set best_device $name
                }
            }
        }
    }

    return $best_device
}

# Create audio input stream
proc create_audio_stream {} {
    set device [find_audio_device]
    set sample_rate [get_config sample_rate]
    set channels [get_config channels]
    set frames_per_buffer [get_config frames_per_buffer]

    log "INFO" "Creating audio stream with device: $device"

    if {[catch {
        pa::open_stream \
            -device $device \
            -rate $sample_rate \
            -channels $channels \
            -frames $frames_per_buffer \
            -format int16 \
            -callback audio_callback
    } stream err]} {
        log "ERROR" "Failed to create audio stream: $err"
        return ""
    }

    set stream_info [$stream info]
    log "INFO" "Audio stream created: $stream"
    log "INFO" "Stream parameters: $stream_info"

    return $stream
}

# Start the transcription process
proc start_transcription {} {
    log "INFO" "Starting real-time speech transcription"

    set stream [get_state stream]
    if {$stream eq ""} {
        log "ERROR" "No audio stream available"
        return 0
    }

    if {[catch {$stream start} err]} {
        log "ERROR" "Failed to start audio stream: $err"
        return 0
    }

    set_state running 1
    log "INFO" "🎤 Transcription started - speak into your microphone!"
    return 1
}

# Stop the transcription process
proc stop_transcription {} {
    log "INFO" "Stopping transcription"

    set stream [get_state stream]
    if {$stream ne ""} {
        $stream stop
        log "INFO" "Audio stream stopped"
    }

    # Get final recognition result
    set recognizer [get_state recognizer]
    if {$recognizer ne ""} {
        if {[catch {$recognizer final_result} final_result]} {
            log "ERROR" "Failed to get final result"
        } else {
            if {$final_result ne "" && $final_result ne "{}"} {
                log "FINAL" "Final result: $final_result"
            }
        }
    }

    set_state running 0
}

# Show final statistics and cleanup
proc cleanup_and_exit {} {
    log "INFO" "Cleaning up resources..."

    # Show final statistics
    set audio_count [get_state audio_count]
    set speech_count [get_state speech_count]
    set partial_count [get_state partial_count]
    set final_count [get_state final_count]

    log "STATS" "Final statistics:"
    log "STATS" "  Audio buffers processed: $audio_count"
    log "STATS" "  Speech events: $speech_count"
    log "STATS" "  Partial results: $partial_count"
    log "STATS" "  Final results: $final_count"

    # Cleanup audio stream
    set stream [get_state stream]
    if {$stream ne ""} {
        if {[catch {$stream stats} stats]} {
            log "INFO" "Stream stats: $stats"
        }
        $stream close
        log "INFO" "Audio stream closed"
    }

    # Cleanup speech recognizer
    set recognizer [get_state recognizer]
    if {$recognizer ne ""} {
        $recognizer close
        log "INFO" "Speech recognizer closed"
    }

    # Cleanup model
    set model [get_state model]
    if {$model ne ""} {
        $model close
        log "INFO" "Speech model closed"
    }

    log "INFO" "✅ Cleanup completed"
}

# Signal handler for graceful shutdown
proc handle_interrupt {} {
    log "INFO" "⏹ Received interrupt signal"
    stop_transcription
    cleanup_and_exit
    exit 0
}

# Main execution
proc main {} {
    log "INFO" "🎤 Real-time Speech Transcription with PortAudio + Vosk"
    log "INFO" "=================================================="

    # Initialize systems
    if {![initialize_systems]} {
        exit 1
    }

    # Load speech model
    set model [load_speech_model]
    if {$model eq ""} {
        exit 1
    }
    set_state model $model

    # Create recognizer
    set recognizer [create_recognizer $model]
    if {$recognizer eq ""} {
        exit 1
    }
    set_state recognizer $recognizer

    # Create audio stream
    set stream [create_audio_stream]
    if {$stream eq ""} {
        exit 1
    }
    set_state stream $stream

    # Setup signal handling
    signal trap SIGINT handle_interrupt
    signal trap SIGTERM handle_interrupt

    # Start transcription
    if {![start_transcription]} {
        cleanup_and_exit
        exit 1
    }

    # Setup automatic stop after reasonable time
    after 60000 {
        log "INFO" "⏰ Stopping after 60 seconds"
        stop_transcription
        cleanup_and_exit
        exit 0
    }

    log "INFO" "Press Ctrl+C to stop, or automatic stop in 60 seconds"
    log "INFO" "=================================================="

    # Run event loop to handle audio callbacks
    vwait forever
}

# Handle the case where signal command might not be available
if {[catch {signal trap SIGINT {}} ]} {
    proc signal {args} {
        # Fallback - signal handling not available
    }
}

# Run the main program
main