#!/usr/bin/env tclsh
# Test suite for WordPiece tokenizer package

# Setup
lappend auto_path [file normalize [file dirname [info script]]/lib]

proc assert {condition msg} {
    if {![uplevel 1 [list expr $condition]]} {
        error "FAIL: $msg"
    }
}

proc test {name body} {
    puts -nonewline "  $name... "
    if {[catch {uplevel 1 $body} err]} {
        puts "FAIL"
        puts "    Error: $err"
        return 0
    }
    puts "OK"
    return 1
}

puts "=== WordPiece Tokenizer Tests ==="
set passed 0
set failed 0

# Load package
puts "\nLoading package..."
if {[catch {package require wordpiece} err]} {
    puts "FAIL: Could not load wordpiece package: $err"
    exit 1
}
puts "Loaded wordpiece [package present wordpiece]"

# Load vocabulary
puts "\nLoading vocabulary..."
set vocab_path [file normalize [file dirname [info script]]/../gec/vocab.txt]
if {![file exists $vocab_path]} {
    puts "FAIL: vocab.txt not found at $vocab_path"
    exit 1
}
set vocab_size [wordpiece::load $vocab_path]
puts "Loaded $vocab_size tokens"

puts "\nRunning tests...\n"

# Test: vocab_size
if {[test "vocab_size returns correct count" {
    assert {[wordpiece::vocab_size] == 30522} "Expected 30522 tokens"
}]} {incr passed} else {incr failed}

# Test: special tokens
if {[test "special token IDs are correct" {
    assert {[wordpiece::token_to_id "\[PAD\]"] == 0} "\[PAD\] should be 0"
    assert {[wordpiece::token_to_id "\[UNK\]"] == 100} "\[UNK\] should be 100"
    assert {[wordpiece::token_to_id "\[CLS\]"] == 101} "\[CLS\] should be 101"
    assert {[wordpiece::token_to_id "\[SEP\]"] == 102} "\[SEP\] should be 102"
    assert {[wordpiece::token_to_id "\[MASK\]"] == 103} "\[MASK\] should be 103"
}]} {incr passed} else {incr failed}

# Test: id_to_token
if {[test "id_to_token returns correct tokens" {
    assert {[wordpiece::id_to_token 101] eq "\[CLS\]"} "ID 101 should be \[CLS\]"
    assert {[wordpiece::id_to_token 102] eq "\[SEP\]"} "ID 102 should be \[SEP\]"
    assert {[wordpiece::id_to_token 7592] eq "hello"} "ID 7592 should be hello"
}]} {incr passed} else {incr failed}

# Test: basic tokenization
if {[test "basic tokenization works" {
    set tokens [wordpiece::encode "hello world"]
    assert {[lindex $tokens 0] == 101} "Should start with \[CLS\]"
    assert {[lindex $tokens end] == 0} "Should end with padding"
    assert {[llength $tokens] == 64} "Default length should be 64"
}]} {incr passed} else {incr failed}

# Test: tokenization preserves content
if {[test "encode/decode roundtrip" {
    set text "the quick brown fox"
    set tokens [wordpiece::encode $text]
    set decoded [wordpiece::decode $tokens]
    assert {$decoded eq $text} "Decoded text should match input"
}]} {incr passed} else {incr failed}

# Test: homophones are different tokens
if {[test "homophones have different token IDs" {
    set their_id [wordpiece::token_to_id "their"]
    set there_id [wordpiece::token_to_id "there"]
    set theyre_id [wordpiece::token_to_id "they"]  ;# "they're" will be split
    assert {$their_id != $there_id} "their and there should have different IDs"
    assert {$their_id == 2037} "their should be ID 2037"
    assert {$there_id == 2045} "there should be ID 2045"
}]} {incr passed} else {incr failed}

# Test: attention mask
if {[test "attention mask marks non-padding tokens" {
    set tokens [wordpiece::encode "hi"]  ;# Short text = lots of padding
    set mask [wordpiece::attention_mask $tokens]
    # [CLS] hi [SEP] + padding
    assert {[lindex $mask 0] == 1} "CLS should be 1"
    assert {[lindex $mask 1] == 1} "First token should be 1"
    assert {[lindex $mask 2] == 1} "SEP should be 1"
    assert {[lindex $mask 3] == 0} "Padding should be 0"
    assert {[lindex $mask end] == 0} "Last token (padding) should be 0"
}]} {incr passed} else {incr failed}

# Test: custom max length
if {[test "custom max_len parameter" {
    set tokens [wordpiece::encode "test" 32]
    assert {[llength $tokens] == 32} "Length should be 32"
}]} {incr passed} else {incr failed}

# Test: lowercase handling
if {[test "text is lowercased" {
    set text "HELLO World"
    set tokens [wordpiece::encode $text]
    set decoded [wordpiece::decode $tokens]
    assert {$decoded eq "hello world"} "Text should be lowercased"
}]} {incr passed} else {incr failed}

# Test: punctuation handling
if {[test "punctuation is tokenized separately" {
    set text "hello, world!"
    set tokens [wordpiece::encode $text]
    set decoded [wordpiece::decode $tokens]
    # Punctuation may have spaces around it after decode
    assert {[string match "*hello*,*world*!*" $decoded]} "Should contain hello, world!"
}]} {incr passed} else {incr failed}

# Test: WordPiece breaks words into subwords
if {[test "WordPiece splits unknown words into subwords" {
    # Even made-up words get tokenized character by character
    set tokens [wordpiece::encode "xyz"]
    set decoded [wordpiece::decode $tokens]
    # The tokenizer will break "xyz" into known subwords
    assert {$decoded eq "xyz"} "Subwords should reconstruct to xyz"
}]} {incr passed} else {incr failed}

# Test: subword tokenization
if {[test "long words are split into subwords" {
    set tokens [wordpiece::encode "unbelievable"]
    # "unbelievable" should be split: un + ##bel + ##iev + ##able or similar
    set decoded [wordpiece::decode $tokens]
    assert {$decoded eq "unbelievable"} "Subwords should reconstruct original"
}]} {incr passed} else {incr failed}

# Summary
puts "\n=== Results ==="
puts "Passed: $passed"
puts "Failed: $failed"
puts "Total:  [expr {$passed + $failed}]"

if {$failed > 0} {
    exit 1
}
puts "\nAll tests passed!"
