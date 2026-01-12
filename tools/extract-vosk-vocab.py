#!/usr/bin/env python3
"""
Extract vocabulary from Vosk/Kaldi words.txt file.

Filters out special tokens (silence, noise markers, epsilon, etc.)
to produce a clean word list for lexicon building.

Source: data/lang/words.txt from Kaldi graph compilation
Origin: gpu:~/vosk-compile/data/lang/words.txt

Build procedure (from compile-graph.sh on gpu):
  1. Dictionary created from db/en.dic via dict.py
  2. Language model: db/en-230k-0.5.lm.gz mixed with extra.txt
  3. utils/prepare_lang.sh generates data/lang/words.txt
  4. Words are those in both the lexicon AND the language model

The words.txt format is: word<space>id
Special tokens to filter:
  - <eps>, <s>, </s>, #0 (Kaldi internal)
  - !SIL (silence)
  - [noise], [uh], [um], etc. (acoustic events)
  - Single punctuation characters

Usage:
    ./extract-vosk-vocab.py <vosk-words.txt> <output-vocab.txt>
"""

import sys
import re


def is_special_token(word: str) -> bool:
    """Check if word is a Kaldi special token."""
    # Kaldi internal tokens
    if word in ('<eps>', '<s>', '</s>', '#0', '!SIL'):
        return True
    # Bracketed tokens like [noise], [uh], [um], [breath], etc.
    if word.startswith('[') and word.endswith(']'):
        return True
    # Angle bracket tokens
    if word.startswith('<') and word.endswith('>'):
        return True
    return False


def extract_vocabulary(words_path: str) -> set[str]:
    """Extract clean vocabulary from Kaldi words.txt."""
    words = set()

    with open(words_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 1:
                word = parts[0]
                if not is_special_token(word):
                    words.add(word.lower())

    return words


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <vosk-words.txt> <output-vocab.txt>", file=sys.stderr)
        print(f"", file=sys.stderr)
        print(f"Extracts clean vocabulary from Kaldi words.txt file.", file=sys.stderr)
        print(f"Filters out special tokens (!SIL, [noise], <eps>, etc.)", file=sys.stderr)
        sys.exit(1)

    words_path = sys.argv[1]
    output_path = sys.argv[2]

    print(f"Extracting vocabulary from {words_path}...", file=sys.stderr)
    words = extract_vocabulary(words_path)
    print(f"  Found {len(words)} words (after filtering special tokens)", file=sys.stderr)

    print(f"Writing {output_path}...", file=sys.stderr)
    with open(output_path, 'w') as f:
        for word in sorted(words):
            f.write(f"{word}\n")

    print(f"Done.", file=sys.stderr)


if __name__ == '__main__':
    main()
