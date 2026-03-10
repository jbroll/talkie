#!/usr/bin/env tclsh
# test_vad_with_audio.tcl - Test Silero VAD against real speech audio

set script_dir [file dirname [file normalize [info script]]]

lappend ::auto_path [file join $script_dir ov lib ov]
package require ov
source [file join $script_dir vad_silero.tcl]

set model_path [file join $script_dir .. models vad silero_vad_ifless.onnx]
set wav_path   [file join $script_dir .. models sherpa-onnx \
    sherpa-onnx-streaming-zipformer-en-2023-06-26 test_wavs 1.wav]

if {[catch {::vad::silero::init $model_path CPU 0.5 16000} err]} {
    puts "FAIL init: $err"; exit 1
}
puts "Model loaded OK\n"

# Read WAV file — skip 44-byte header (standard PCM WAV)
set fh [open $wav_path rb]
# Read RIFF header to find data chunk
set header [read $fh 12]
binary scan $header a4ia4 riff_id file_size wave_id
if {$riff_id ne "RIFF" || $wave_id ne "WAVE"} { puts "Not a WAV file"; exit 1 }

# Scan chunks until we find "data"
while {1} {
    set chunk_hdr [read $fh 8]
    if {[string length $chunk_hdr] < 8} { puts "No data chunk found"; exit 1 }
    binary scan $chunk_hdr a4i chunk_id chunk_size
    if {$chunk_id eq "data"} break
    seek $fh $chunk_size current
}
set pcm [read $fh $chunk_size]
close $fh

puts "WAV data: [string length $pcm] bytes ([expr {[string length $pcm]/2}] samples @ 16kHz)"
puts "Duration: [format %.2f [expr {[string length $pcm]/2/16000.0}]]s\n"

# Check peak amplitude
binary scan $pcm s* all_samples
set peak 0
foreach s $all_samples { if {abs($s) > $peak} { set peak [expr {abs($s)}] } }
puts "Peak amplitude: $peak / 32767 ([format %.1f [expr {20*log10($peak/32767.0)}]] dBFS)\n"

# Feed through Silero in 512-sample (1024-byte) chunks and report probabilities
puts [format "%-8s %-8s %-8s" "time(s)" "prob" "speech?"]
puts [string repeat - 30]

set offset 0
set chunk_bytes 1024  ;# 512 samples * 2 bytes
set time_s 0.0
set n_speech 0
set n_total 0
set prob_sum 0.0

while {$offset + $chunk_bytes <= [string length $pcm]} {
    set chunk [string range $pcm $offset [expr {$offset + $chunk_bytes - 1}]]
    set prob [::vad::silero::process $chunk]
    if {$prob >= 0} {
        set speech [expr {$prob > 0.5}]
        if {$speech} { incr n_speech }
        incr n_total
        set prob_sum [expr {$prob_sum + $prob}]
        puts [format "%-8.3f %-8.4f %-8s" $time_s $prob [expr {$speech ? "SPEECH" : "silence"}]]
    }
    set offset [expr {$offset + $chunk_bytes}]
    set time_s [expr {$time_s + 512.0/16000.0}]
}

puts [string repeat - 30]
puts "Speech frames: $n_speech / $n_total ([format %.0f [expr {100.0*$n_speech/$n_total}]]%)"
puts "Mean prob:     [format %.4f [expr {$prob_sum/$n_total}]]"
puts "Peak prob:     (see above)"
