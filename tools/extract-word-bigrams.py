#!/usr/bin/env python3
"""Extract word bigram probabilities for homophone words from ARPA LM.

Extracts P(word | prev_word) and P(next_word | word) for words in homophone groups.

Usage:
    zcat en-230k-0.5.lm.gz | python3 extract-word-bigrams.py > word-bigrams.tsv
"""

import sys
from collections import defaultdict

# Curated homophone groups
HOMOPHONE_GROUPS = [
    {'their', 'there', "they're"},
    {'to', 'too', 'two'},
    {'your', "you're"},
    {'its', "it's"},
    {'know', 'no'},
    {'hear', 'here'},
    {'write', 'right'},
    {'whose', "who's"},
    {'were', 'where', "we're"},
    {'then', 'than'},
    {'affect', 'effect'},
    {'accept', 'except'},
    {'brake', 'break'},
    {'peace', 'piece'},
    {'weather', 'whether'},
    {'by', 'buy', 'bye'},
    {'wait', 'weight'},
    {'new', 'knew'},
    {'scene', 'seen'},
    {'threw', 'through'},
    {'whole', 'hole'},
    {'meat', 'meet'},
    {'would', 'wood'},
    {'one', 'won'},
    {'our', 'hour'},
    {'for', 'four'},
    {'be', 'bee'},
    {'sea', 'see'},
    {'bare', 'bear'},
    {'fair', 'fare'},
    {'pair', 'pear'},
    {'rain', 'reign'},
    {'tail', 'tale'},
    {'waist', 'waste'},
    {'weak', 'week'},
    {'which', 'witch'},
]

# Build set of all homophone words
HOMOPHONE_WORDS = set()
for group in HOMOPHONE_GROUPS:
    HOMOPHONE_WORDS.update(group)

def main():
    # Store bigrams involving homophone words
    # Format: (word1, word2) -> log_prob
    bigrams = {}

    in_bigrams = False
    count = 0

    print("Reading bigrams from stdin...", file=sys.stderr)
    for line in sys.stdin:
        line = line.strip()

        if line == '\\2-grams:':
            in_bigrams = True
            continue
        elif line.startswith('\\') and in_bigrams:
            break

        if not in_bigrams:
            continue

        parts = line.split('\t')
        if len(parts) < 2:
            continue

        try:
            log_prob = float(parts[0])
        except ValueError:
            continue

        words = parts[1].split()
        if len(words) != 2:
            continue

        w1, w2 = words[0].lower(), words[1].lower()

        # Skip sentence markers
        if w1 in ['<s>', '</s>'] or w2 in ['<s>', '</s>']:
            continue

        # Only keep bigrams where either word is a homophone
        if w1 in HOMOPHONE_WORDS or w2 in HOMOPHONE_WORDS:
            bigrams[(w1, w2)] = log_prob
            count += 1

        if count % 100000 == 0 and count > 0:
            print(f"Found {count} relevant bigrams...", file=sys.stderr)

    print(f"Total bigrams: {count}", file=sys.stderr)

    # Output
    print("# Word bigrams for homophones")
    print("# Format: word1<tab>word2<tab>log_prob")
    for (w1, w2), log_prob in sorted(bigrams.items()):
        print(f"{w1}\t{w2}\t{log_prob:.6f}")

if __name__ == '__main__':
    main()
