# Test utilities for Talkie tests

# Utility to reset all module states for clean testing
proc reset_test_state {} {
    # Reset audio module
    if {[namespace exists ::audio]} {
        set ::audio::energy_buffer {}
        set ::audio::initialization_complete 0
        set ::audio::noise_floor 0
        set ::audio::speech_floor 0
        set ::audio::last_speech_time 0
        set ::audio::audio_buffer_list {}
    }

    # Reset global variables
    set ::transcribing 0
    set ::audiolevel 0
    set ::confidence 0

    # Clear test result variables
    if {[info exists ::test_results]} {
        set ::test_results {}
    }
    if {[info exists ::test_partial_text]} {
        set ::test_partial_text ""
    }
    if {[info exists ::test_final_results]} {
        set ::test_final_results {}
    }

    # Clear mock typed text
    if {[info commands ::uinput::clear_typed_text] ne ""} {
        ::uinput::clear_typed_text
    }
}

# Utility to simulate a sequence of audio energy values
proc simulate_audio_sequence {energy_values} {
    set timestamp 0
    foreach energy $energy_values {
        ::audio::set_mock_energy $energy
        ::audio::audio_callback "mock_stream" $timestamp "mock_data"
        incr timestamp 100
    }
}

# Utility to create mock Vosk results
proc create_mock_result {text confidence {partial 0}} {
    if {$partial} {
        return "{\"partial\": \"$text\"}"
    } else {
        return "{\"alternatives\": \[{\"text\": \"$text\", \"confidence\": $confidence}\]}"
    }
}

# Utility to verify energy buffer contents
proc verify_energy_buffer {expected_values} {
    set actual $::audio::energy_buffer
    if {[llength $actual] != [llength $expected_values]} {
        return "Length mismatch: expected [llength $expected_values], got [llength $actual]"
    }

    for {set i 0} {$i < [llength $expected_values]} {incr i} {
        set exp [lindex $expected_values $i]
        set act [lindex $actual $i]
        if {abs($exp - $act) > 0.001} {
            return "Value mismatch at index $i: expected $exp, got $act"
        }
    }

    return "ok"
}