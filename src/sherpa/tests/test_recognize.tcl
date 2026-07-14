lappend auto_path [file join [file dirname [info script]] .. lib]
package require sherpa

set model_dir [file normalize [file join [file dirname [info script]] \
    ../../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26]]

set rec [sherpa::create_recognizer \
    -encoder [file join $model_dir encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx] \
    -decoder [file join $model_dir decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx] \
    -joiner  [file join $model_dir joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx] \
    -tokens  [file join $model_dir tokens.txt] \
    -rate 16000]

# Read a 16kHz mono 16-bit PCM WAV, skip 44-byte header
set f [open [file join $model_dir test_wavs 0.wav] rb]
set wav [read $f]
close $f
set pcm [string range $wav 44 end]

# Append 3s of trailing silence so the endpoint rule (2.4s) can fire
append pcm [binary format c* [lrepeat [expr {16000 * 3 * 2}] 0]]

# Feed in 3200-byte (100ms) chunks; collect partial + endpoint
set saw_endpoint 0
set last_partial ""
for {set i 0} {$i < [string length $pcm]} {incr i 3200} {
    set chunk [string range $pcm $i [expr {$i+3199}]]
    set r [$rec process $chunk]
    if {[dict get $r endpoint]} { set saw_endpoint 1 }
    if {[dict get $r partial] ne ""} { set last_partial [dict get $r partial] }
}
set final [$rec final-result]
set text [string trim [dict get $final text]]
$rec close

puts "partial='$last_partial' final='$text' endpoint=$saw_endpoint"
if {[string length $text] < 3} { puts "FAIL: transcript too short"; exit 1 }
if {!$saw_endpoint} { puts "FAIL: endpoint never fired after trailing silence"; exit 1 }
puts "PASS"
exit 0
