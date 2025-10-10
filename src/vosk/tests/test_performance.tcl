#!/usr/bin/env tclsh
# test_performance.tcl - Analyze Vosk processing performance

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Analyzing Vosk processing performance..."

# Load vosk package
package require vosk
Vosk_Init

# Load model
set model_path "../../models/vosk-model-en-us-0.22-lgraph"
set model [vosk::load_model -path $model_path]
puts "✓ Model loaded: $model"

# Simplified WAV reader (from previous test)
proc read_wav_file {filename} {
    set fp [open $filename rb]
    set riff_header [read $fp 12]
    binary scan $riff_header "a4 i a4" riff file_size wave

    if {$riff ne "RIFF" || $wave ne "WAVE"} {
        close $fp
        error "Not a valid WAV file"
    }

    # Find fmt chunk
    while {![eof $fp]} {
        set chunk_header [read $fp 8]
        if {[string length $chunk_header] < 8} break
        binary scan $chunk_header "a4 i" chunk_id chunk_size
        if {$chunk_id eq "fmt "} {
            set fmt_data [read $fp $chunk_size]
            binary scan $fmt_data "s s i i s s" \
                audio_format num_channels sample_rate byte_rate block_align bits_per_sample
            break
        } else {
            seek $fp $chunk_size current
        }
    }

    # Find data chunk
    seek $fp 12 start
    while {![eof $fp]} {
        set chunk_header [read $fp 8]
        if {[string length $chunk_header] < 8} break
        binary scan $chunk_header "a4 i" chunk_id chunk_size
        if {$chunk_id eq "data"} {
            set audio_data [read $fp $chunk_size]
            break
        } else {
            seek $fp $chunk_size current
        }
    }
    close $fp
    return [list $audio_data $sample_rate $num_channels $bits_per_sample]
}

# Performance analysis function
proc analyze_performance {model wav_file chunk_size_bytes} {
    puts "\n🎵 Performance Analysis: [file tail $wav_file]"
    puts "   Chunk size: $chunk_size_bytes bytes"

    set wav_info [read_wav_file $wav_file]
    set audio_data [lindex $wav_info 0]
    set sample_rate [lindex $wav_info 1]
    set num_channels [lindex $wav_info 2]
    set bits_per_sample [lindex $wav_info 3]

    # Calculate audio duration
    set bytes_per_sample [expr {$bits_per_sample / 8}]
    set total_samples [expr {[string length $audio_data] / $bytes_per_sample}]
    set audio_duration [expr {double($total_samples) / $sample_rate}]

    puts "   Audio: ${audio_duration}s, $sample_rate Hz, $num_channels ch, $bits_per_sample bit"

    # Calculate chunk duration
    set samples_per_chunk [expr {$chunk_size_bytes / $bytes_per_sample}]
    set chunk_duration [expr {double($samples_per_chunk) / $sample_rate}]

    puts "   Chunk duration: ${chunk_duration}s ([expr {$chunk_duration * 1000}]ms)"

    # Create recognizer
    set recognizer [$model create_recognizer -rate $sample_rate]

    # Process and time
    set data_len [string length $audio_data]
    set chunks [expr {($data_len + $chunk_size_bytes - 1) / $chunk_size_bytes}]

    puts "   Processing $chunks chunks..."

    set start_time [clock milliseconds]
    set chunk_times {}

    for {set i 0} {$i < $chunks} {incr i} {
        set chunk_start [clock milliseconds]

        set start [expr {$i * $chunk_size_bytes}]
        set end [expr {min($start + $chunk_size_bytes - 1, $data_len - 1)}]
        set chunk [string range $audio_data $start $end]

        if {[string length $chunk] > 0} {
            set result [$recognizer process $chunk]
        }

        set chunk_end [clock milliseconds]
        set chunk_time [expr {$chunk_end - $chunk_start}]
        lappend chunk_times $chunk_time
    }

    set final_result [$recognizer final_result]
    set end_time [clock milliseconds]

    # Calculate performance metrics
    set total_processing_time [expr {$end_time - $start_time}]
    set avg_chunk_time [expr {[tcl::mathop::+ {*}$chunk_times] / double($chunks)}]
    set realtime_factor [expr {double($total_processing_time) / 1000.0 / $audio_duration}]

    puts "   📊 Performance Results:"
    puts "      Total processing time: ${total_processing_time}ms"
    puts "      Average per chunk: ${avg_chunk_time}ms"
    puts "      Real-time factor: [format %.3f $realtime_factor]x"

    if {$realtime_factor < 1.0} {
        puts "      ✅ FASTER than real-time ([format %.1f [expr {(1.0 - $realtime_factor) * 100}]]% faster)"
    } else {
        puts "      ❌ SLOWER than real-time ([format %.1f [expr {($realtime_factor - 1.0) * 100}]]% slower)"
    }

    # Extract recognized text
    if {[regexp {"text"\s*:\s*"([^"]*)"} $final_result -> text]} {
        puts "   📝 Recognition: '[string range $text 0 80]...'"
    }

    $recognizer close
    return $realtime_factor
}

# Test different chunk sizes
set test_files {
    "../../test_audio/voice-sample.wav"
    "../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/test_wavs/1.wav"
}

set chunk_sizes [list 1600 3200 6400 16000]
# 1600: ~0.05s at 16kHz
# 3200: ~0.1s at 16kHz (current)
# 6400: ~0.2s at 16kHz
# 16000: ~0.5s at 16kHz

foreach file $test_files {
    if {[file exists $file]} {
        puts "\n[string repeat "=" 60]"
        puts "Testing file: [file tail $file]"

        foreach chunk_size $chunk_sizes {
            analyze_performance $model $file $chunk_size
        }
    }
}

$model close
puts "\n✅ Performance analysis completed!"