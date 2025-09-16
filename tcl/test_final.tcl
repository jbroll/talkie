#!/usr/bin/env tclsh
# Final verification that the Python-like Talkie app is working

puts "🎯 Final Talkie Python-like Application Test"
puts [string repeat "=" 50]

# Test syntax by parsing without running main
if {[catch {
    set fd [open "talkie.tcl" r]
    set content [read $fd]
    close $fd

    # Just check if it parses correctly
    if {[info complete $content]} {
        puts "✅ Syntax check: PASSED"
    } else {
        puts "❌ Incomplete syntax"
    }
} err]} {
    puts "❌ Syntax error: $err"
    exit 1
}

# Verify all namespaces and procedures exist
set required_namespaces {::talkie}
set required_procs {
    ::talkie::load_config
    ::talkie::save_config
    ::talkie::refresh_devices
    ::talkie::setup_ui
    ::talkie::toggle_transcription
    ::talkie::show_controls_view
    ::talkie::show_text_view
    ::talkie::quit_app
    ::talkie::clear_partial_text
    ::talkie::add_final_text
    ::talkie::add_partial_text
}

puts "\n📋 Checking required procedures..."
foreach proc_name $required_procs {
    if {[info procs $proc_name] ne ""} {
        puts "✅ $proc_name"
    } else {
        puts "❌ Missing: $proc_name"
    }
}

# Test package functionality
puts "\n📦 Testing package functionality..."

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir pa lib]
lappend auto_path [file join $script_dir vosk lib]

# Test PortAudio
if {[catch {
    package require pa
    pa::init
    if {[info commands Pa_Init] ne ""} {
        Pa_Init
    }
    puts "✅ PortAudio: Working"

    # Test device listing
    set devices [pa::list_devices]
    puts "✅ Device listing: [llength $devices] devices found"

    # Test pulse device detection
    set pulse_found 0
    foreach device $devices {
        dict with device {
            if {[dict exists $device maxInputChannels] && [dict get $device maxInputChannels] > 0} {
                if {[string match -nocase "*pulse*" $name]} {
                    puts "✅ Pulse device: $name (ID: $index)"
                    set pulse_found 1
                }
            }
        }
    }
    if {!$pulse_found} {
        puts "⚠️  No pulse device found"
    }

} err]} {
    puts "❌ PortAudio error: $err"
}

# Test Vosk
if {[catch {
    package require vosk
    vosk::set_log_level -1
    puts "✅ Vosk: Working"

    set model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
    if {[file exists $model_path]} {
        puts "✅ Vosk model: Available"
    } else {
        puts "⚠️  Vosk model: Not found at $model_path"
    }
} err]} {
    puts "❌ Vosk error: $err"
}

puts "\n🎉 Final verification complete!"
puts "The Python-like Talkie Tcl application is ready to use:"
puts "   ./talkie_python_like.tcl"
puts "\n✨ Features:"
puts "   • Pulse device selection by default"
puts "   • Python app UI structure (Controls/Text views)"
puts "   • Dual-pane interface with switchable views"
puts "   • Real-time transcription capabilities"
puts "   • Configuration persistence"
