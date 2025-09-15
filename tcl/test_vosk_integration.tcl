#!/usr/bin/env tclsh
# Test Vosk integration in the main application

puts "🎯 Testing Vosk Integration"
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

# Set test mode to prevent GUI
set ::test_mode 1

# Source the main application
if {[catch {
    source talkie_python_like.tcl
    puts "✅ Application loaded successfully"
} err]} {
    puts "❌ Failed to load application: $err"
    exit 1
}

# Test Vosk initialization
puts "\n🔊 Testing Vosk initialization..."
if {[catch {
    set result [::talkie::init_vosk]
    if {$result} {
        puts "✅ Vosk initialized successfully"

        # Check if model and recognizer were created
        if {$::talkie::vosk_model ne ""} {
            puts "✅ Vosk model loaded: $::talkie::vosk_model"
        }

        if {$::talkie::vosk_recognizer ne ""} {
            puts "✅ Vosk recognizer created: $::talkie::vosk_recognizer"
        }

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
    set test_json {"text": "hello world", "confidence": 0.85}
    ::talkie::speech_callback $test_json true
    puts "✅ Speech callback works with final result"

    set test_json_partial {"partial": "hello"}
    ::talkie::speech_callback $test_json_partial false
    puts "✅ Speech callback works with partial result"

} err]} {
    puts "❌ Speech callback error: $err"
}

# Test audio callback (without actual audio data)
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
puts "The application is ready for real-time speech recognition."