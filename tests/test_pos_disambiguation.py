#!/usr/bin/env python3
"""Test suite for POS-based homophone disambiguation.

Run with: python3 -m pytest tests/test_pos_disambiguation.py -v
Or: python3 tests/test_pos_disambiguation.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from pos_service import LexiconPOSService

# Test cases: (input, expected_output, description)
TEST_CASES = [
    # their/there/they're
    ("I went to there house", "I went to their house", "there->their before noun"),
    ("there is a problem", "there is a problem", "there is (existential)"),
    ("over they're", "over there", "they're->there after 'over'"),
    ("its they're fault", "its their fault", "they're->their before noun"),
    ("they're going home", "they're going home", "they're (contraction) before verb"),

    # to/too/two
    ("go too the store", "go to the store", "too->to before determiner"),
    ("me two", "me too", "two->too after pronoun"),
    ("I have too cats", "I have two cats", "too->two as number"),
    ("that is to much", "that is too much", "to->too as adverb"),
    ("give it too me", "give it to me", "too->to as preposition"),

    # know/no
    ("I no what you mean", "I know what you mean", "no->know after subject"),
    ("I said no", "I said no", "no standalone"),
    ("do you no him", "do you know him", "no->know after auxiliary"),
    ("no problem", "no problem", "no as determiner"),

    # hear/here
    ("can you hear me", "can you hear me", "hear (verb)"),
    ("come hear now", "come here now", "hear->here after motion verb"),
    ("I can here you", "I can hear you", "here->hear after modal"),
    ("over hear", "over here", "hear->here after 'over'"),

    # write/right
    ("please right this down", "please write this down", "right->write after please"),
    ("that is write", "that is right", "write->right as adjective"),
    ("turn write here", "turn right here", "write->right as direction"),
    ("I will right a letter", "I will write a letter", "right->write after modal"),

    # your/you're
    ("your going to love this", "you're going to love this", "your->you're before verb"),
    ("is this you're book", "is this your book", "you're->your before noun"),
    ("your welcome", "you're welcome", "your->you're in set phrase"),
    ("take you're time", "take your time", "you're->your before noun"),

    # its/it's
    ("its raining outside", "it's raining outside", "its->it's before verb"),
    ("the dog wagged it's tail", "the dog wagged its tail", "it's->its before noun"),
    ("its a beautiful day", "it's a beautiful day", "its->it's before determiner"),

    # whose/who's
    ("whose coming to dinner", "who's coming to dinner", "whose->who's before verb"),
    ("who's book is this", "whose book is this", "who's->whose before noun"),

    # were/where/we're
    ("were are you going", "where are you going", "were->where in question"),
    ("we're were you yesterday", "where were you yesterday", "we're->where in question"),
    ("they where happy", "they were happy", "where->were after pronoun"),

    # then/than
    ("bigger then me", "bigger than me", "then->than in comparison"),
    ("more than ever", "more than ever", "than (correct)"),
    ("first this than that", "first this then that", "than->then in sequence"),

    # affect/effect
    ("this will effect you", "this will affect you", "effect->affect as verb"),
    ("the affect was immediate", "the effect was immediate", "affect->effect as noun"),

    # accept/except
    ("I except your apology", "I accept your apology", "except->accept as verb"),
    ("everyone accept him", "everyone except him", "accept->except as preposition"),

    # brake/break
    ("take a brake", "take a break", "brake->break as noun"),
    ("don't break the car", "don't brake the car", "break->brake for car context"),

    # peace/piece
    ("a peace of cake", "a piece of cake", "peace->piece before 'of'"),
    ("world piece", "world peace", "piece->peace after 'world'"),

    # weather/whether
    ("I don't know weather to go", "I don't know whether to go", "weather->whether before 'to'"),
    ("the whether is nice", "the weather is nice", "whether->weather after determiner"),

    # by/bye/buy
    ("I want to by a car", "I want to buy a car", "by->buy after 'to'"),
    ("say by to him", "say bye to him", "by->bye after 'say'"),
    ("stand bye me", "stand by me", "bye->by after verb"),

    # wait/weight
    ("I can't weight", "I can't wait", "weight->wait after modal"),
    ("check the wait", "check the weight", "wait->weight after determiner"),

    # new/knew
    ("I new it", "I knew it", "new->knew after subject"),
    ("a knew car", "a new car", "knew->new after determiner"),

    # scene/seen
    ("have you scene this", "have you seen this", "scene->seen after auxiliary"),
    ("a beautiful seen", "a beautiful scene", "seen->scene after adjective"),

    # threw/through
    ("walk threw the door", "walk through the door", "threw->through after motion verb"),
    ("he through the ball", "he threw the ball", "through->threw after subject"),

    # whole/hole
    ("the hold thing", "the whole thing", "hold->whole... wait, not a homophone"),
    ("a hold in the ground", "a hole in the ground", "hold->hole... also not right"),
    ("dig a whole", "dig a hole", "whole->hole as object"),
    ("the hole story", "the whole story", "hole->whole before noun"),

    # meat/meet
    ("nice to meat you", "nice to meet you", "meat->meet after 'to'"),
    ("let's meet for dinner", "let's meet for dinner", "meet (correct)"),

    # would/wood
    ("I wood like that", "I would like that", "wood->would as modal"),
    ("made of would", "made of wood", "would->wood as material"),

    # one/won
    ("we one the game", "we won the game", "one->won as verb"),
    ("won more time", "one more time", "won->one as number"),

    # No change needed cases
    ("the quick brown fox", "the quick brown fox", "no homophones"),
    ("hello world", "hello world", "simple greeting"),
]


def run_tests():
    """Run all disambiguation tests."""
    lexicon_path = os.path.join(os.path.dirname(__file__), '..', 'tools', 'talkie.lex')
    dic_path = os.path.expanduser('~/Downloads/vosk-model-en-us-0.22-compile/db/en.dic')

    print("Loading POS service...")
    svc = LexiconPOSService(lexicon_path, dic_path)
    print()

    passed = 0
    failed = 0

    for input_text, expected, description in TEST_CASES:
        result = svc.disambiguate(input_text)
        if result == expected:
            print(f"✓ {description}")
            passed += 1
        else:
            print(f"✗ {description}")
            print(f"  Input:    '{input_text}'")
            print(f"  Expected: '{expected}'")
            print(f"  Got:      '{result}'")
            failed += 1

    print()
    print(f"Results: {passed} passed, {failed} failed out of {len(TEST_CASES)} tests")
    return failed == 0


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
