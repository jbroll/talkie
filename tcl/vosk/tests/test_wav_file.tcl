#!/usr/bin/env tclsh
# test_wav_file.tcl - Test Vosk with real WAV file

package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]

puts "Testing Vosk with WAV file..."

# Load vosk package
package require vosk
Vosk_Init

# Load model
set model_path "../../models/vosk-model-en-us-0.22-lgraph"
set model [vosk::load_model -path $model_path]
puts "✓ Model loaded: $model"

# We'll create recognizers dynamically based on the WAV file sample rate
set recognizer ""

# Function to read WAV file and extract raw audio data
proc read_wav_file {filename} {
    set fp [open $filename rb]

    # Read RIFF header
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
            # Skip this chunk
            seek $fp $chunk_size current
        }
    }

    # Find data chunk
    seek $fp 12 start  ;# Back to start after RIFF header
    while {![eof $fp]} {
        set chunk_header [read $fp 8]
        if {[string length $chunk_header] < 8} break

        binary scan $chunk_header "a4 i" chunk_id chunk_size

        if {$chunk_id eq "data"} {
            set audio_data [read $fp $chunk_size]
            break
        } else {
            # Skip this chunk
            seek $fp $chunk_size current
        }
    }

    close $fp

    puts "WAV file info:"
    puts "  Sample rate: $sample_rate Hz"
    puts "  Channels: $num_channels"
    puts "  Bits per sample: $bits_per_sample"
    puts "  Data size: [string length $audio_data] bytes"

    return [list $audio_data $sample_rate $num_channels $bits_per_sample]
}

# Test with different audio files
set test_files {
    "../../test_audio/voice-sample.wav"
    "../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/test_wavs/0.wav"
    "../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/test_wavs/1.wav"
    "../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/test_wavs/8k.wav"
}

foreach wav_file $test_files {
    if {[file exists $wav_file]} {
        puts "\n🎵 Processing: $wav_file"

        try {
            set wav_info [read_wav_file $wav_file]
            set audio_data [lindex $wav_info 0]
            set sample_rate [lindex $wav_info 1]
            set num_channels [lindex $wav_info 2]
            set bits_per_sample [lindex $wav_info 3]

            # Create recognizer with the correct sample rate for this file
            if {$recognizer ne ""} {
                $recognizer close
            }
            set recognizer [$model create_recognizer -rate $sample_rate]
            puts "  ✓ Created recognizer for $sample_rate Hz"

            # Convert to mono if stereo (simple: take left channel)
            if {$num_channels == 2 && $bits_per_sample == 16} {
                puts "  Converting stereo to mono..."
                set mono_data ""
                set data_len [string length $audio_data]
                for {set i 0} {$i < $data_len} {incr i 4} {
                    # Take only left channel (first 2 bytes of each 4-byte stereo sample)
                    append mono_data [string range $audio_data $i [expr {$i + 1}]]
                }
                set audio_data $mono_data
            }

            # Process in chunks for better recognition
            set chunk_size 3200  ;# ~0.1 second at 16kHz
            set data_len [string length $audio_data]
            set chunks [expr {($data_len + $chunk_size - 1) / $chunk_size}]

            puts "  Processing $chunks chunks of audio data..."

            for {set i 0} {$i < $chunks} {incr i} {
                set start [expr {$i * $chunk_size}]
                set end [expr {min($start + $chunk_size - 1, $data_len - 1)}]
                set chunk [string range $audio_data $start $end]

                if {[string length $chunk] > 0} {
                    set result [$recognizer process $chunk]

                    # Parse JSON to extract text
                    if {[regexp {"text"\s*:\s*"([^"]*)"} $result -> text]} {
                        if {$text ne ""} {
                            puts "    Partial: '$text'"
                        }
                    }
                }
            }

            # Get final result
            set final [$recognizer final_result]
            puts "  🎯 Final result: $final"

            # Parse final JSON to extract text and confidence
            if {[regexp {"text"\s*:\s*"([^"]*)"} $final -> text]} {
                puts "  📝 Recognized text: '$text'"
            }
            if {[regexp {"confidence"\s*:\s*([0-9.]+)} $final -> confidence]} {
                puts "  📊 Confidence: $confidence"
            }

            # Reset recognizer for next file
            $recognizer reset

        } on error {err} {
            puts "  ❌ Error processing $wav_file: $err"
        }
    } else {
        puts "⚠️  File not found: $wav_file"
    }
}

puts "\n🧹 Cleanup..."
if {$recognizer ne ""} {
    $recognizer close
}
$model close

puts "✅ WAV file test completed!"