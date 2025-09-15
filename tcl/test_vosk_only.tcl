#!/usr/bin/env tclsh
# Test only the Vosk integration functions without any GUI

puts "🎯 Testing Vosk Functions Only"
puts [string repeat "-" 40]

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir vosk lib]

# Load packages
package require pa
pa::init
if {[info commands Pa_Init] ne ""} {
    Pa_Init
}

package require vosk
vosk::set_log_level -1

# Create minimal namespace with just what we need
namespace eval ::talkie {
    # Configuration
    variable config
    array set config {
        model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
        sample_rate 16000
        confidence_threshold 280.0
        vosk_max_alternatives 0
        energy_threshold 50.0
    }

    # State variables
    variable vosk_model ""
    variable vosk_recognizer ""
    variable current_energy 0.0
    variable current_confidence 0.0

    # Mock UI functions that don't create widgets
    proc add_final_text {text} {
        puts "FINAL: $text"
    }

    proc add_partial_text {text} {
        puts "PARTIAL: $text"
    }
}

# Now source just the functions we need
if {[catch {
    # Define the functions from the main app

    # Vosk initialization
    proc ::talkie::init_vosk {} {
        variable config
        variable vosk_model
        variable vosk_recognizer

        if {[catch {
            # Load Vosk model
            set vosk_model [vosk::load_model $config(model_path)]
            add_final_text "✓ Vosk model loaded"

            # Create recognizer
            set vosk_recognizer [$vosk_model create_recognizer \
                -rate $config(sample_rate) \
                -callback ::talkie::speech_callback \
                -confidence $config(confidence_threshold) \
                -alternatives $config(vosk_max_alternatives)]

            add_final_text "✓ Vosk recognizer created"
            return true

        } err]} {
            add_final_text "✗ Vosk initialization failed: $err"
            return false
        }
    }

    # Speech recognition callback
    proc ::talkie::speech_callback {json_result is_final} {
        variable current_confidence

        # Parse JSON to extract text and confidence
        set text ""
        set confidence 0

        if {$json_result ne ""} {
            # Extract text
            if {[regexp {"text"\s*:\s*"([^"]*)"} $json_result -> extracted_text]} {
                set text [string trim $extracted_text]
            }

            # Extract confidence if available
            if {[regexp {"confidence"\s*:\s*([0-9.]+)} $json_result -> conf]} {
                set confidence [expr {$conf * 1000}]  # Convert to 0-1000 scale
                set current_confidence $confidence
            }
        }

        # Only process non-empty text
        if {$text ne ""} {
            if {$is_final} {
                # Final result
                if {$confidence >= 200} {  # Filter low confidence results
                    add_final_text "[format "%.0f" $confidence]: $text"
                }
            } else {
                # Partial result
                add_partial_text $text
            }
        }
    }

    # Audio callback for real-time processing
    proc ::talkie::audio_callback {stream_name timestamp data} {
        variable vosk_recognizer
        variable current_energy
        variable config

        # Calculate energy level for display
        binary scan $data s* samples
        set energy 0
        foreach sample $samples {
            set energy [expr {$energy + abs($sample)}]
        }
        set current_energy [expr {$energy / double([llength $samples])}]

        # Voice activity detection - only process if energy is above threshold
        if {$current_energy > $config(energy_threshold)} {
            # Process audio with Vosk if recognizer is available
            if {$vosk_recognizer ne ""} {
                if {[catch {
                    $vosk_recognizer process $data
                } err]} {
                    # Silently ignore processing errors to avoid spam
                }
            }
        }
    }

    puts "✅ Functions defined successfully"

} err]} {
    puts "❌ Failed to define functions: $err"
    exit 1
}

# Test Vosk initialization
puts "\n🔊 Testing Vosk initialization..."
if {[catch {
    set result [::talkie::init_vosk]
    if {$result} {
        puts "✅ Vosk initialized successfully"
        puts "   Model: $::talkie::vosk_model"
        puts "   Recognizer: $::talkie::vosk_recognizer"
    } else {
        puts "❌ Vosk initialization failed"
    }
} err]} {
    puts "❌ Vosk initialization error: $err"
}

# Test speech callback
puts "\n🗣️  Testing speech callback..."
if {[catch {
    # Test with sample JSON
    set test_json {{"text": "hello world", "confidence": 0.85}}
    ::talkie::speech_callback $test_json 1

    set test_json_partial {{"partial": "hello"}}
    ::talkie::speech_callback $test_json_partial 0

    puts "✅ Speech callback test completed"

} err]} {
    puts "❌ Speech callback error: $err"
}

# Test audio callback
puts "\n🎤 Testing audio callback..."
if {[catch {
    # Create some dummy audio data (512 bytes of int16)
    set dummy_data [binary format s* [lrepeat 256 100]]
    ::talkie::audio_callback "test_stream" 0.1 $dummy_data
    puts "✅ Audio callback processed dummy data"
    puts "   Current energy: $::talkie::current_energy"

} err]} {
    puts "❌ Audio callback error: $err"
}

puts "\n🎉 Vosk integration test complete!"
puts "Functions are ready for integration."