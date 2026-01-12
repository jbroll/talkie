#!/usr/bin/env python3
"""
Extract word -> POS mapping from Wiktionary JSONL dump.

Creates a simple TSV file: word<tab>POS
Where POS is converted to Moby-style single-letter codes.

Input: kaikki.org Wiktionary English dump (JSONL)
Output: wiktionary-pos.tsv
"""

import sys
import json

# Wiktionary POS to Moby POS mapping
WIKT_TO_MOBY = {
    'noun': 'N',
    'verb': 'V',
    'adj': 'A',
    'adv': 'v',
    'name': 'N',        # proper nouns are still nouns
    'pron': 'r',
    'prep': 'P',
    'conj': 'C',
    'det': 'D',
    'intj': '!',
    'num': 'N',         # numerals as nouns
    'particle': 'v',    # treat as adverb
    'article': 'D',     # articles are determiners
    'contraction': None,  # skip - we handle these specially
    # Skip: phrase, prep_phrase, proverb, prefix, suffix, symbol, etc.
}


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <wiktionary.jsonl> <output.tsv>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    print(f"Processing {input_path}...", file=sys.stderr)

    # Collect all POS for each word (a word can be multiple POS)
    word_pos = {}
    entries = 0
    skipped = 0

    with open(input_path, 'r') as f:
        for line in f:
            entries += 1
            if entries % 100000 == 0:
                print(f"  Processed {entries} entries...", file=sys.stderr)

            d = json.loads(line)
            word = d.get('word', '').lower()
            wikt_pos = d.get('pos')

            if not word or not wikt_pos:
                skipped += 1
                continue

            moby_pos = WIKT_TO_MOBY.get(wikt_pos)
            if not moby_pos:
                skipped += 1
                continue

            if word not in word_pos:
                word_pos[word] = set()
            word_pos[word].add(moby_pos)

    print(f"  Total entries: {entries}", file=sys.stderr)
    print(f"  Skipped: {skipped}", file=sys.stderr)
    print(f"  Unique words: {len(word_pos)}", file=sys.stderr)

    # Write output
    print(f"Writing {output_path}...", file=sys.stderr)
    with open(output_path, 'w') as out:
        for word in sorted(word_pos.keys()):
            # Combine POS codes (e.g., "NV" for noun+verb)
            pos = ''.join(sorted(word_pos[word]))
            out.write(f"{word}\t{pos}\n")

    print(f"Done. Wrote {len(word_pos)} entries.", file=sys.stderr)


if __name__ == '__main__':
    main()
