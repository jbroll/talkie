#!/usr/bin/env python3
"""Extract trigrams that distinguish homophones differently than bigrams.

Only keeps trigrams where the trigram probability would select a different
homophone than the bigram-only approach.

Usage:
    zcat en-230k-0.5.lm.gz | python3 extract-distinguishing-trigrams.py bigrams.tsv > trigrams.tsv
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

# Build homophone lookup
HOMOPHONE_WORDS = set()
WORD_TO_GROUP = {}
for group in HOMOPHONE_GROUPS:
    HOMOPHONE_WORDS.update(group)
    for word in group:
        WORD_TO_GROUP[word] = group


def load_bigrams(path):
    """Load bigrams into lookup dict."""
    bigrams = {}
    with open(path, 'r') as f:
        for line in f:
            if line.startswith('#'):
                continue
            parts = line.strip().split('\t')
            if len(parts) == 3:
                w1, w2, log_prob = parts[0], parts[1], float(parts[2])
                bigrams[(w1, w2)] = log_prob
    return bigrams


def bigram_score(bigrams, prev_word, word, next_word):
    """Score using bigrams: P(word|prev) + P(next|word)."""
    score = 0.0
    if prev_word:
        score += bigrams.get((prev_word, word), -6.0)
    if next_word:
        score += bigrams.get((word, next_word), -6.0)
    return score


def bigram_winner(bigrams, prev_word, homophones, next_word):
    """Find which homophone wins with bigram scoring."""
    best_word = None
    best_score = float('-inf')
    for word in homophones:
        score = bigram_score(bigrams, prev_word, word, next_word)
        if score > best_score:
            best_score = score
            best_word = word
    return best_word, best_score


def main():
    if len(sys.argv) < 2:
        print("Usage: zcat lm.gz | python3 extract-distinguishing-trigrams.py bigrams.tsv", file=sys.stderr)
        sys.exit(1)

    bigram_path = sys.argv[1]
    print(f"Loading bigrams from {bigram_path}...", file=sys.stderr)
    bigrams = load_bigrams(bigram_path)
    print(f"Loaded {len(bigrams)} bigrams", file=sys.stderr)

    # Collect all trigrams involving homophones
    # Key: (prev_word, next_word, homophone_group_key) -> {homophone: log_prob}
    trigram_sets = defaultdict(dict)

    in_trigrams = False
    count = 0

    print("Reading trigrams from stdin...", file=sys.stderr)
    for line in sys.stdin:
        line = line.strip()

        if line == '\\3-grams:':
            in_trigrams = True
            continue
        elif line.startswith('\\') and in_trigrams:
            break

        if not in_trigrams:
            continue

        parts = line.split('\t')
        if len(parts) < 2:
            continue

        try:
            log_prob = float(parts[0])
        except ValueError:
            continue

        words = parts[1].split()
        if len(words) != 3:
            continue

        w1, w2, w3 = words[0].lower(), words[1].lower(), words[2].lower()

        # Skip sentence markers
        if any(w in ['<s>', '</s>'] for w in [w1, w2, w3]):
            continue

        # Only care about trigrams where middle is a homophone
        if w2 in HOMOPHONE_WORDS:
            group = WORD_TO_GROUP[w2]
            group_key = tuple(sorted(group))
            trigram_sets[(w1, w3, group_key)][w2] = log_prob
            count += 1

        if count % 500000 == 0 and count > 0:
            print(f"Processed {count} homophone trigrams...", file=sys.stderr)

    print(f"Total homophone trigrams: {count}", file=sys.stderr)
    print(f"Unique (prev, next, group) contexts: {len(trigram_sets)}", file=sys.stderr)

    # Find distinguishing trigrams
    distinguishing = []

    for (prev_word, next_word, group_key), trigram_probs in trigram_sets.items():
        group = set(group_key)

        # Need at least 2 homophones in this context to compare
        if len(trigram_probs) < 2:
            continue

        # What would bigrams pick?
        bigram_best, _ = bigram_winner(bigrams, prev_word, group, next_word)

        # What would trigrams pick?
        trigram_best = max(trigram_probs, key=lambda w: trigram_probs[w])

        # If they differ, this is a distinguishing context!
        if bigram_best != trigram_best:
            for word, log_prob in trigram_probs.items():
                distinguishing.append((prev_word, word, next_word, log_prob, bigram_best, trigram_best))

    print(f"Distinguishing trigrams: {len(distinguishing)}", file=sys.stderr)

    # Output
    print("# Distinguishing trigrams (where trigram picks different homophone than bigram)")
    print("# Format: prev<tab>homophone<tab>next<tab>log_prob<tab>bigram_pick<tab>trigram_pick")
    for prev_word, word, next_word, log_prob, bi_pick, tri_pick in sorted(distinguishing):
        print(f"{prev_word}\t{word}\t{next_word}\t{log_prob:.6f}\t{bi_pick}\t{tri_pick}")


if __name__ == '__main__':
    main()
