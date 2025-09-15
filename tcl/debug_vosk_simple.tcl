#!/usr/bin/env tclsh
# Simple Vosk test

set script_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $script_dir vosk lib]

puts "=== Simple Vosk Test ==="

puts "Loading Vosk package..."
package require vosk

puts "Initializing Vosk..."
Vosk_Init

puts "Available commands:"
foreach cmd [info commands vosk::*] {
    puts "  $cmd"
}

set model_path "/home/john/Downloads/vosk-model-en-us-0.22-lgraph"
puts "Model path: $model_path"
puts "Model exists: [file exists $model_path]"

if {[file exists $model_path]} {
    puts "Loading model..."
    set model [vosk::load_model -path $model_path]
    puts "Model result: '$model'"
    puts "Model length: [string length $model]"

    puts "Creating recognizer..."
    set recognizer [$model create_recognizer -rate 16000]
    puts "Recognizer result: '$recognizer'"
    puts "Recognizer length: [string length $recognizer]"
}