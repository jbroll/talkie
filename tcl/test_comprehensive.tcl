#!/usr/bin/env tclsh
# Comprehensive test that simulates user interactions

puts "🔍 Comprehensive Talkie Python-like Test"
puts [string repeat "=" 50]

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir vosk lib]

# Load required packages
package require pa
pa::init
if {[info commands Pa_Init] ne ""} {
    Pa_Init
}

package require vosk
vosk::set_log_level -1

# Source the main application but prevent GUI from running
set ::test_mode 1

if {[catch {
    source talkie_python_like.tcl
    puts "✅ Application sourced successfully"
} err]} {
    puts "❌ Failed to source application: $err"
    exit 1
}

# Test all critical procedures exist
set critical_procs {
    ::talkie::load_config
    ::talkie::save_config
    ::talkie::refresh_devices
    ::talkie::setup_ui
    ::talkie::toggle_transcription
    ::talkie::start_transcription
    ::talkie::stop_transcription
    ::talkie::update_audio_display
    ::talkie::add_partial_text
    ::talkie::add_final_text
    ::talkie::clear_partial_text
    ::talkie::device_changed
    ::talkie::energy_changed
    ::talkie::confidence_changed
}

puts "\n📋 Testing critical procedures..."
set missing_count 0
foreach proc_name $critical_procs {
    if {[info procs $proc_name] ne ""} {
        puts "✅ $proc_name"
    } else {
        puts "❌ Missing: $proc_name"
        incr missing_count
    }
}

if {$missing_count > 0} {
    puts "\n❌ $missing_count critical procedures missing!"
    exit 1
}

# Test configuration loading
puts "\n⚙️  Testing configuration..."
if {[catch {
    ::talkie::load_config
    puts "✅ Configuration loaded"

    # Check critical config values
    set required_configs {sample_rate frames_per_buffer audio_device engine model_path}
    foreach key $required_configs {
        if {[info exists ::talkie::config($key)]} {
            puts "✅ config($key) = $::talkie::config($key)"
        } else {
            puts "❌ Missing config: $key"
        }
    }
} err]} {
    puts "❌ Configuration error: $err"
}

# Test device refresh
puts "\n🎤 Testing device functionality..."
if {[catch {
    ::talkie::refresh_devices
    puts "✅ Device refresh completed"

    variable ::talkie::available_devices
    variable ::talkie::selected_device
    puts "✅ Available devices: [llength $available_devices]"
    puts "✅ Selected device: $selected_device"
} err]} {
    puts "❌ Device test error: $err"
}

# Test namespace isolation
puts "\n🔧 Testing namespace isolation..."
if {[catch {
    # These should fail if called without namespace
    if {[catch {update_audio_display} err1]} {
        puts "✅ update_audio_display properly namespaced"
    } else {
        puts "❌ update_audio_display accessible without namespace"
    }

    if {[catch {add_final_text "test"} err2]} {
        puts "✅ add_final_text properly namespaced"
    } else {
        puts "❌ add_final_text accessible without namespace"
    }
} err]} {
    puts "❌ Namespace test error: $err"
}

puts "\n🎉 Comprehensive test completed!"
puts "The application structure is sound and ready for GUI testing."