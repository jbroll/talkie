#!/usr/bin/env python3
"""
Generate pruned lexicon from:
1. Original en.dic filtered to only words in LM
2. Generated pronunciations for LM words not in en.dic
3. New domain words from extra.txt

Run from the compile/ directory.
"""
import phonetisaurus
import sys
import gzip
import os

# First, load LM vocabulary to know what words to keep
lm_words = set()
lm_file = 'lgraph-base.lm.gz'
print(f'Loading LM vocabulary from {lm_file}...', file=sys.stderr, flush=True)

with gzip.open(lm_file, 'rt') as f:
    in_unigrams = False
    for line in f:
        line = line.strip()
        if line == '\\1-grams:':
            in_unigrams = True
            continue
        elif line.startswith('\\') and line.endswith(':'):
            if in_unigrams:
                break
            continue
        if in_unigrams and line:
            parts = line.split('\t')
            if len(parts) >= 2:
                word = parts[1]
                if not word.startswith('<'):
                    lm_words.add(word)

print(f'LM vocabulary: {len(lm_words)} words', file=sys.stderr, flush=True)

words = {}

# Load original lexicon, but only keep words in LM
skipped = 0
for line in open('db/en.dic'):
    items = line.split()
    word = items[0]
    base_word = word.split('(')[0] if '(' in word else word

    if base_word not in lm_words:
        skipped += 1
        continue

    if word not in words:
        words[word] = []
    words[word].append(' '.join(items[1:]))

print(f'Loaded {len(words)} words from en.dic (skipped {skipped} not in LM)', file=sys.stderr)

# Load extra.dic if exists (domain-specific, always include)
try:
    for line in open('db/extra.dic'):
        line = line.strip()
        if not line:
            continue
        items = line.split()
        if items[0] not in words:
            words[items[0]] = []
        words[items[0]].append(' '.join(items[1:]))
except:
    pass

# Load generated pronunciations for LM words not in dictionary
if os.path.exists('missing_pronunciations.txt'):
    for line in open('missing_pronunciations.txt'):
        items = line.split()
        if items[0] not in words:
            words[items[0]] = []
        words[items[0]].append(' '.join(items[1:]))

print(f'After adding missing words: {len(words)} words', file=sys.stderr)

# Generate pronunciations for new domain words
new_words = set()
for line in open('db/extra.txt'):
    for w in line.split():
        if w not in words:
            new_words.add(w)

if new_words:
    print(f'Generating pronunciations for {len(new_words)} new domain words', file=sys.stderr)
    for w, phones in phonetisaurus.predict(new_words, 'db/en-g2p/en.fst'):
        words[w] = []
        words[w].append(' '.join(phones))

print(f'Final lexicon: {len(words)} words', file=sys.stderr)

for w, phones in sorted(words.items()):
    for p in phones:
        print(w, p)
