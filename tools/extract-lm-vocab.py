#!/usr/bin/env python3
"""
Extract vocabulary from ARPA language model.

Only includes words that have non-zero probability in the unigram section.
This filters out words that are in words.txt but not actually used by the LM.

Usage:
    ./extract-lm-vocab.py <lm.arpa.gz> <output-words.txt>

Example:
    ./extract-lm-vocab.py ~/Downloads/vosk-model-en-us-0.22-compile/db/en-230k-0.5.lm.gz lm-vocab.txt
"""

import sys
import gzip
import re


def extract_unigrams(lm_path: str) -> set[str]:
    """Extract unigram words from ARPA language model."""
    words = set()
    in_unigrams = False

    opener = gzip.open if lm_path.endswith('.gz') else open

    with opener(lm_path, 'rt', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()

            # Look for unigram section
            if line == '\\1-grams:':
                in_unigrams = True
                continue

            # End of unigrams
            if line.startswith('\\') and in_unigrams:
                break

            if in_unigrams and line:
                # ARPA format: prob<tab>word[<tab>backoff]
                parts = line.split('\t')
                if len(parts) >= 2:
                    word = parts[1]
                    # Skip special tokens
                    if not word.startswith('<') and not word.startswith('#'):
                        words.add(word.lower())

    return words


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <lm.arpa[.gz]> <output-words.txt>", file=sys.stderr)
        print(f"", file=sys.stderr)
        print(f"Extracts words with non-zero probability from ARPA language model.", file=sys.stderr)
        sys.exit(1)

    lm_path = sys.argv[1]
    output_path = sys.argv[2]

    print(f"Extracting unigrams from {lm_path}...", file=sys.stderr)
    words = extract_unigrams(lm_path)
    print(f"  Found {len(words)} words", file=sys.stderr)

    print(f"Writing {output_path}...", file=sys.stderr)
    with open(output_path, 'w') as f:
        for word in sorted(words):
            f.write(f"{word}\n")

    print(f"Done.", file=sys.stderr)


if __name__ == '__main__':
    main()
