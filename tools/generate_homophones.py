#!/usr/bin/env python3
"""Generate homophones.json from pronunciation dictionary.

Groups words by pronunciation (with optional hw→w normalization for
modern English where "wh" is typically pronounced as "w").

Usage:
    python3 generate_homophones.py [--normalize-wh] [-o output.json]

Requires:
    - Pronunciation dictionary: ~/Downloads/vosk-model-en-us-0.22-compile/db/en.dic
    - Vocabulary file: models/vosk/lm-test/graph/words.txt (optional, for filtering)
"""

import json
import sys
import argparse
from pathlib import Path
from collections import defaultdict


def load_pronunciations(dic_path: Path, normalize_wh: bool = True) -> dict[str, list[tuple]]:
    """Load word pronunciations from dictionary.

    Args:
        dic_path: Path to pronunciation dictionary
        normalize_wh: If True, treat 'h w' as 'w' (modern English)

    Returns:
        dict mapping word -> list of pronunciation tuples
    """
    word_prons = defaultdict(list)

    with open(dic_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 2:
                continue

            word = parts[0].lower()
            # Skip variant pronunciations like "word(2)"
            if '(' in word:
                word = word.split('(')[0]

            pron = tuple(parts[1:])

            # Normalize: treat 'h w' as 'w' for wh- words
            if normalize_wh and len(pron) >= 2 and pron[0] == 'h' and pron[1] == 'w':
                pron = pron[1:]  # Remove leading 'h'

            if pron not in word_prons[word]:
                word_prons[word].append(pron)

    return dict(word_prons)


def load_vocabulary(vocab_path: Path) -> set[str]:
    """Load vocabulary from words.txt file."""
    vocab = set()
    with open(vocab_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if parts and not parts[0].startswith('<') and not parts[0].startswith('#'):
                vocab.add(parts[0].lower())
    return vocab


def build_homophones(word_prons: dict[str, list[tuple]], vocab: set[str] | None = None) -> dict[str, list[str]]:
    """Build homophone groups from pronunciations.

    Args:
        word_prons: dict mapping word -> list of pronunciation tuples
        vocab: Optional vocabulary to filter words

    Returns:
        dict mapping word -> list of homophones (including self)
    """
    # Group words by pronunciation
    pron_to_words = defaultdict(set)

    for word, prons in word_prons.items():
        # Filter to vocabulary if provided
        if vocab and word not in vocab:
            continue

        for pron in prons:
            pron_to_words[pron].add(word)

    # Build homophone index
    homophones = {}
    for pron, words in pron_to_words.items():
        if len(words) > 1:
            word_list = sorted(words)
            for word in words:
                if word in homophones:
                    # Merge with existing homophones
                    existing = set(homophones[word])
                    existing.update(word_list)
                    homophones[word] = sorted(existing)
                else:
                    homophones[word] = word_list

    return homophones


def main():
    parser = argparse.ArgumentParser(description='Generate homophones.json')
    parser.add_argument('--normalize-wh', action='store_true', default=True,
                        help='Treat "wh" as "w" (default: True)')
    parser.add_argument('--no-normalize-wh', action='store_false', dest='normalize_wh',
                        help='Keep "wh" distinct from "w"')
    parser.add_argument('-o', '--output', type=Path,
                        default=Path(__file__).parent.parent / 'data' / 'homophones.json',
                        help='Output file path')
    parser.add_argument('--dic', type=Path,
                        default=Path.home() / 'Downloads/vosk-model-en-us-0.22-compile/db/en.dic',
                        help='Pronunciation dictionary path')
    parser.add_argument('--vocab', type=Path,
                        default=Path(__file__).parent.parent / 'models/vosk/lm-test/graph/words.txt',
                        help='Vocabulary file path (optional)')
    args = parser.parse_args()

    # Check dictionary exists
    if not args.dic.exists():
        print(f"Error: Dictionary not found: {args.dic}", file=sys.stderr)
        sys.exit(1)

    print(f"Loading pronunciations from {args.dic}...", file=sys.stderr)
    print(f"  Normalize wh→w: {args.normalize_wh}", file=sys.stderr)
    word_prons = load_pronunciations(args.dic, normalize_wh=args.normalize_wh)
    print(f"  Loaded {len(word_prons)} words", file=sys.stderr)

    # Load vocabulary if available
    vocab = None
    if args.vocab.exists():
        print(f"Loading vocabulary from {args.vocab}...", file=sys.stderr)
        vocab = load_vocabulary(args.vocab)
        print(f"  Loaded {len(vocab)} vocabulary words", file=sys.stderr)
    else:
        print(f"  No vocabulary filter (file not found: {args.vocab})", file=sys.stderr)

    # Build homophones
    print("Building homophone groups...", file=sys.stderr)
    homophones = build_homophones(word_prons, vocab)

    # Statistics
    unique_groups = set()
    for word, alts in homophones.items():
        unique_groups.add(tuple(sorted(alts)))

    print(f"  {len(homophones)} words with homophones", file=sys.stderr)
    print(f"  {len(unique_groups)} unique homophone groups", file=sys.stderr)

    # Sample some interesting groups
    interesting = ['whether', 'weather', 'their', 'there', 'write', 'right', 'sea', 'see']
    print("\nSample homophones:", file=sys.stderr)
    for word in interesting:
        if word in homophones:
            print(f"  {word}: {homophones[word]}", file=sys.stderr)

    # Write output
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, 'w') as f:
        json.dump(homophones, f, separators=(',', ':'))

    print(f"\nWritten to {args.output}", file=sys.stderr)


if __name__ == '__main__':
    main()
