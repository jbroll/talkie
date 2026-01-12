#!/usr/bin/env python3
"""Extract POS bigram probabilities from ARPA LM.

Reads word bigrams from ARPA file, maps words to POS using lexicon,
and outputs POS transition probabilities.

Usage:
    zcat en-230k-0.5.lm.gz | python3 extract-pos-bigrams.py lexicon.lex > pos-bigrams.tsv
"""

import sys
from collections import defaultdict
import math

def load_lexicon(path):
    """Load word -> POS mapping from lexicon."""
    word_pos = {}
    with open(path, 'r') as f:
        for line in f:
            if line.startswith('#'):
                continue
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                word = parts[0].lower()
                pos_raw = parts[1]
                # Strip source prefixes
                pos = pos_raw.lstrip('$~^%')
                # Get first POS character (simplified)
                pos_chars = set()
                for p in pos.replace('+', ''):
                    if p in 'NVtiAvCPr!Dh':
                        pos_chars.add(p)
                if pos_chars:
                    # Use most "significant" POS (rough priority)
                    for prio in ['N', 'V', 't', 'i', 'A', 'v', 'P', 'D', 'r', 'C', '!', 'h']:
                        if prio in pos_chars:
                            word_pos[word] = prio
                            break
    return word_pos

def main():
    if len(sys.argv) < 2:
        print("Usage: zcat lm.gz | python3 extract-pos-bigrams.py lexicon.lex", file=sys.stderr)
        sys.exit(1)

    lexicon_path = sys.argv[1]
    print(f"Loading lexicon from {lexicon_path}...", file=sys.stderr)
    word_pos = load_lexicon(lexicon_path)
    print(f"Loaded {len(word_pos)} word->POS mappings", file=sys.stderr)

    # Count POS bigrams
    pos_bigram_count = defaultdict(lambda: defaultdict(float))
    pos_unigram_count = defaultdict(float)

    in_bigrams = False
    bigram_count = 0

    print("Reading bigrams from stdin...", file=sys.stderr)
    for line in sys.stdin:
        line = line.strip()

        if line == '\\2-grams:':
            in_bigrams = True
            continue
        elif line.startswith('\\') and in_bigrams:
            # End of bigrams section
            break

        if not in_bigrams:
            continue

        # Parse bigram line: log_prob word1 word2 [backoff]
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

        # Get POS for each word
        pos1 = word_pos.get(w1)
        pos2 = word_pos.get(w2)

        if pos1 and pos2:
            # Convert log prob to probability and accumulate
            prob = 10 ** log_prob
            pos_bigram_count[pos1][pos2] += prob
            pos_unigram_count[pos1] += prob
            bigram_count += 1

            if bigram_count % 1000000 == 0:
                print(f"Processed {bigram_count} bigrams...", file=sys.stderr)

    print(f"Total bigrams with POS: {bigram_count}", file=sys.stderr)

    # Normalize to get P(pos2 | pos1)
    print("# POS bigram transition probabilities: P(pos2 | pos1)")
    print("# Format: pos1<tab>pos2<tab>probability")

    for pos1 in sorted(pos_bigram_count.keys()):
        total = pos_unigram_count[pos1]
        if total == 0:
            continue
        for pos2 in sorted(pos_bigram_count[pos1].keys()):
            prob = pos_bigram_count[pos1][pos2] / total
            if prob > 0.001:  # Only output significant transitions
                print(f"{pos1}\t{pos2}\t{prob:.6f}")

if __name__ == '__main__':
    main()
