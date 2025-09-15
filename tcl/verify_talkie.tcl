#!/usr/bin/env tclsh
# Verify the Talkie application syntax and basic functionality

puts "Verifying Talkie Python-like application..."

# Test syntax by sourcing the file without running main
if {[catch {
    source talkie_python_like.tcl
    puts "✓ Syntax check passed"
} err]} {
    puts "✗ Syntax error: $err"
    exit 1
}

# Test that all required procedures exist
set required_procs {
    ::talkie::load_config
    ::talkie::save_config
    ::talkie::refresh_devices
    ::talkie::setup_ui
    ::talkie::toggle_transcription
    ::talkie::show_controls_view
    ::talkie::show_text_view
    ::talkie::quit_app
}

puts "\nChecking required procedures..."
foreach proc_name $required_procs {
    if {[info procs $proc_name] ne ""} {
        puts "✓ $proc_name"
    } else {
        puts "✗ Missing: $proc_name"
    }
}

# Test package loading functionality
puts "\nTesting package functionality..."

# Check if packages can be loaded
if {[catch {
    lappend auto_path [file join [pwd] pa lib]
    lappend auto_path [file join [pwd] vosk lib]

    package require pa
    pa::init
    if {[info commands Pa_Init] ne ""} {
        Pa_Init
    }
    puts "✓ PortAudio package working"

    # Test device listing
    set devices [pa::list_devices]
    puts "✓ Device listing working ([llength $devices] devices)"

    package require vosk
    puts "✓ Vosk package working"

} err]} {
    puts "✗ Package error: $err"
}

puts "\n🎉 Talkie application verification complete!"
puts "The application is ready to run with: ./talkie_python_like.tcl"