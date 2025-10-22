

namespace eval ::threshold {
    variable initialization_complete 0
    variable speech_energy_buffer {}
    variable speechlevel 0

    variable segment_sum    0
    variable segment_count  0

    variable energy_buffer {}
    variable noise_floor 0
    variable noise_threshold 0

    variable last_is_speech_time 0
    variable last_segment_end_time 0

    proc ready {} {
        variable initialization_complete

        return $initialization_complete
    }

    proc reset {} {
        variable last_is_speech_time
        variable last_segment_end_time
        set last_is_speech_time 0
        set last_segment_end_time 0
    }

    proc accept { conf } {
        variable segment_sum
        variable segment_count

        set confidence_threshold [get_dynamic_confidence_threshold]

        if { $conf >= $confidence_threshold} {
            update_speech_energy 
            puts "THRS-ACCEPT: $conf > $confidence_threshold"
        } else {
            puts "THRS-FILTER: $conf < $confidence_threshold"
        }


        return [expr { $conf >= $confidence_threshold }]
    }

    proc is_speech { audiolevel in_segment_timestamp } {
        variable initialization_complete
        variable energy_buffer
        variable segment_sum
        variable segment_count
        variable noise_floor
        variable noise_threshold
        variable last_is_speech_time
        variable last_segment_end_time

        update_energy_stats $audiolevel

        if {!$initialization_complete} {
            set progress [expr {[llength $energy_buffer] * 100 / $::config(initialization_samples)}]
            if {$progress % 10 == 0} {
                after idle [list partial_text "Calibrating audio environment... ${progress}%"]
            }
            return false
        }

        set in_segment [expr {$in_segment_timestamp != 0}]
        set current_time [clock milliseconds]

        # Track when segments transition from active to inactive
        if {!$in_segment && $last_is_speech_time > 0} {
            set last_segment_end_time $current_time
            set last_is_speech_time 0
        }

        if { $in_segment } {
            set segment_sum [expr { $segment_sum + $audiolevel }]
            incr segment_count
        }

        set noise_threshold [expr {$noise_floor * $::config(audio_threshold_multiplier)}]
        set raw_is_speech [expr { $audiolevel > $noise_threshold }]

        # Spike suppression: Prevent noise spikes from starting/continuing segments
        set is_speech $raw_is_speech

        # CASE 1: Spike during active segment (after silence has started within segment)
        if {$in_segment && $raw_is_speech && $last_is_speech_time > 0} {
            set time_since_last_speech [expr {($current_time - $last_is_speech_time) / 1000.0}]

            if {$time_since_last_speech > $::config(spike_suppression_seconds)} {
                set is_speech 0
                puts "SPIKE-IN-SEG: Ignoring noise spike ${time_since_last_speech}s after speech in segment (audio=$audiolevel)"
            }
        }

        # CASE 2: Spike trying to START a new segment shortly after previous segment ended
        if {!$in_segment && $raw_is_speech && $last_segment_end_time > 0} {
            set time_since_segment_end [expr {($current_time - $last_segment_end_time) / 1000.0}]

            if {$time_since_segment_end < $::config(spike_suppression_seconds)} {
                set is_speech 0
                puts "SPIKE-NEW-SEG: Preventing new segment ${time_since_segment_end}s after previous ended (audio=$audiolevel)"
            }
        }

        # Update last speech time when we have confirmed speech
        if {$is_speech} {
            set last_is_speech_time $current_time
        }

        # Debug: Show every sample when in or near a segment
        if {$in_segment || $is_speech || $raw_is_speech} {
            puts "SPEECH-DEBUG: audio=$audiolevel threshold=$noise_threshold floor=$noise_floor raw=$raw_is_speech final=$is_speech in_seg=$in_segment"
        }

        # Debug output every 50 samples to see adaptation
        if {[llength $energy_buffer] % 50 == 0} {
            puts "NOISE-FLOOR: floor=$noise_floor threshold=$noise_threshold current=$audiolevel is_speech=$is_speech in_segment=$in_segment buf_size=[llength $energy_buffer]"
        }

        return $is_speech
    }

    proc get_dynamic_confidence_threshold {} {
        variable segment_sum
        variable segment_count
        variable speechlevel
        variable initialization_complete
        variable noise_threshold

        set base_threshold $::config(confidence_threshold)

        if {!$initialization_complete || $speechlevel == 0} {
            return $base_threshold
        }

        set speech_min [expr {$speechlevel * $::config(speech_min_multiplier)}]
        set speech_max [expr {$speechlevel * $::config(speech_max_multiplier)}]
        set max_penalty $::config(max_confidence_penalty)

        if { $segment_count > 0 } {
            set current_energy [expr $segment_sum/$segment_count]
        } else {
            set current_energy $::audiolevel
        }

        set ratio [expr {($current_energy - $speech_min) / ($speech_max - $speech_min)}]
        set penalty [expr { clip(0, $max_penalty * (1.0 - $ratio), $max_penalty) }]

        print THRS-CONFID level $current_energy min $speech_min max $speech_max penalty $penalty : $speechlevel/$noise_threshold

        return [expr {$base_threshold + $penalty}]
    }


    proc update_energy_stats {energy} {
        variable energy_buffer
        variable noise_floor
        variable initialization_complete

        lappend energy_buffer $energy
        set energy_buffer [lrange $energy_buffer end-600 end]

        if {!$initialization_complete && [llength $energy_buffer] >= $::config(initialization_samples)} {
            complete_initialization
        }

        if {[llength $energy_buffer] % 50 == 0 && [llength $energy_buffer] >= 50} {
            calculate_percentiles
        }
    }

    proc calculate_percentiles {} {
        variable energy_buffer
        variable noise_floor

        set sorted [lsort -real $energy_buffer]
        set count [llength $sorted]

        if {$count >= 10} {
            set old_floor $noise_floor
            set percentile_index [expr {int($count * $::config(noise_floor_percentile) / 100.0)}]
            set noise_floor [lindex $sorted $percentile_index]

            # Show min/max/median for context
            set min_val [lindex $sorted 0]
            set max_val [lindex $sorted end]
            set median_val [lindex $sorted [expr {$count / 2}]]

            puts "PERCENTILE-CALC: old_floor=$old_floor new_floor=$noise_floor (percentile=${::config(noise_floor_percentile)}% at index $percentile_index of $count) min=$min_val median=$median_val max=$max_val"
        }
    }

    proc complete_initialization {} {
        variable initialization_complete
        variable noise_floor
        variable speechlevel

        calculate_percentiles

        if {$speechlevel < $noise_floor * 1.5} {
            set speechlevel [expr {$noise_floor * 3.0}]
        }

        set initialization_complete 1
        after idle {partial_text "✓ Audio calibration complete - Ready for transcription"}

        puts "DEBUG: Initialization complete - Noise floor: $noise_floor, Speech level: $speechlevel"
    }

    proc update_speech_energy {} {
        variable segment_sum
        variable segment_count
        variable speech_energy_buffer
        variable speechlevel

        if { !$segment_count } { return }

        set energy [expr $segment_sum/$segment_count]

        set segment_sum 0
        set segment_count 0

        lappend speech_energy_buffer $energy
        set speech_energy_buffer [lrange $speech_energy_buffer end-10 end]

        set sorted [lsort -real $speech_energy_buffer]
        set count [llength $sorted]
        set speechlevel [lindex $sorted [expr {int($count/2)}]]
    }
}
