#!/usr/bin/env tclsh
# Test suite for textproc macro substitution

set script_dir [file dirname [file normalize [info script]]]

# Set up package paths
::tcl::tm::path add "$::env(HOME)/lib/tcl8/site-tcl"
package require jbr::unix

source [file join $script_dir .. textproc.tcl]

# Test framework
set ::test_count 0
set ::test_passed 0
set ::test_failed 0

proc test {name body expected} {
    incr ::test_count
    textproc_reset  ;# Reset state between tests

    set result [uplevel 1 $body]
    if {$result eq $expected} {
        incr ::test_passed
        puts "  PASS: $name"
    } else {
        incr ::test_failed
        puts "  FAIL: $name"
        puts "        Expected: [list $expected]"
        puts "        Got:      [list $result]"
    }
}

proc test_section {name} {
    puts "\n=== $name ==="
}

# ============================================================
# Word Boundary Tests
# ============================================================
test_section "Word Boundary Matching"

test "period at end is replaced" {
    textproc "hello world period"
} "Hello world."

test "period in middle of word is NOT replaced" {
    textproc "I do this periodically"
} "I do this periodically"

test "period as separate word mid-sentence stays" {
    # "period" mid-sentence should NOT be replaced (end-only)
    textproc "the period is important here"
} "The period is important here"

test "question mark at end is replaced" {
    textproc "how are you question mark"
} "How are you?"

test "exclamation mark at end is replaced" {
    textproc "wow exclamation mark"
} "Wow!"

test "exclamation point at end is replaced" {
    textproc "amazing exclamation point"
} "Amazing!"

# ============================================================
# End-of-Utterance Tests
# ============================================================
test_section "End-of-Utterance Matching"

test "new line at end is replaced" {
    textproc "first line new line"
} "First line\n"

test "new line mid-sentence is kept" {
    textproc "start a new line of code"
} "Start a new line of code"

test "newline at end is replaced" {
    textproc "end here newline"
} "End here\n"

test "new paragraph at end is replaced" {
    textproc "end of section new paragraph"
} "End of section\n\n"

# ============================================================
# Mid-Sentence Punctuation Tests
# ============================================================
test_section "Mid-Sentence Punctuation"

test "comma is replaced anywhere" {
    textproc "hello comma world"
} "Hello, world"

test "comma at end" {
    textproc "trailing comma"
} "Trailing,"

test "colon is replaced" {
    textproc "note colon important"
} "Note: important"

test "semicolon is replaced" {
    textproc "first semicolon second"
} "First; second"

test "semi colon (two words) is replaced" {
    textproc "one semi colon two"
} "One; two"

test "hyphen is replaced" {
    textproc "well hyphen known"
} "Well-known"

test "dash is replaced" {
    textproc "hello dash world"
} "Hello-world"

# ============================================================
# Capitalization Tests
# ============================================================
test_section "Capitalization"

test "first word is capitalized" {
    textproc "hello world"
} "Hello world"

test "word after period is capitalized" {
    textproc_reset
    textproc "first period"
    textproc "second sentence"
} " Second sentence"

test "word after question mark is capitalized" {
    textproc_reset
    textproc "what question mark"
    textproc "next sentence"
} " Next sentence"

test "word after exclamation is capitalized" {
    textproc_reset
    textproc "wow exclamation mark"
    textproc "next part"
} " Next part"

# ============================================================
# Multi-word Pattern Tests
# ============================================================
test_section "Multi-word Patterns"

test "question mark (two words) is matched" {
    textproc "really question mark"
} "Really?"

test "exclamation mark (two words) is matched" {
    textproc "great exclamation mark"
} "Great!"

test "new paragraph (two words) is matched" {
    textproc "end new paragraph"
} "End\n\n"

# ============================================================
# Quotes and Brackets
# ============================================================
test_section "Quotes and Brackets"

test "open quote is replaced" {
    textproc "he said open quote hello"
} {He said " hello}

test "close quote is replaced" {
    textproc "world close quote she replied"
} {World " she replied}

test "open paren is replaced" {
    textproc "see appendix open paren a close paren"
} {See appendix ( a )}

# ============================================================
# Symbols
# ============================================================
test_section "Symbols"

test "apostrophe is replaced" {
    textproc "don apostrophe t"
} {Don ' t}

test "ellipsis is replaced" {
    textproc "wait ellipsis what"
} {Wait... what}

test "at sign is replaced" {
    textproc "email at sign example"
} {Email @ example}

test "ampersand is replaced" {
    textproc "tom ampersand jerry"
} {Tom & jerry}

test "hashtag is replaced" {
    textproc "hashtag trending"
} {# trending}

test "asterisk is replaced" {
    textproc "note asterisk important"
} {Note * important}

test "slash is replaced" {
    textproc "yes slash no"
} {Yes / no}

test "underscore is replaced" {
    textproc "my underscore variable"
} {My _ variable}

test "dollar sign is replaced" {
    textproc "costs dollar sign fifty"
} {Costs $ fifty}

test "percent is replaced" {
    textproc "fifty percent off"
} {Fifty % off}

test "plus sign is replaced" {
    textproc "one plus sign two"
} {One + two}

test "equals is replaced" {
    textproc "x equals five"
} {X = five}

# ============================================================
# Edge Cases
# ============================================================
test_section "Edge Cases"

test "empty string" {
    textproc ""
} ""

test "single word" {
    textproc "hello"
} "Hello"

test "only punctuation macro" {
    textproc "period"
} "."

test "multiple punctuation in sequence" {
    textproc_reset
    textproc "hello period"
    textproc "next comma then more period"
} " Next, then more."

test "case insensitive matching" {
    textproc "hello PERIOD"
} "Hello."

test "case insensitive question mark" {
    textproc "what QUESTION MARK"
} "What?"

# ============================================================
# Summary
# ============================================================
puts "\n=========================================="
puts "Tests: $::test_count  Passed: $::test_passed  Failed: $::test_failed"
if {$::test_failed > 0} {
    puts "SOME TESTS FAILED"
    exit 1
} else {
    puts "ALL TESTS PASSED"
    exit 0
}
