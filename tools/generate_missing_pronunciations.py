#!/usr/bin/env python3
"""
Generate pronunciations for words in lgraph that are missing from en.dic.

The vosk-model-en-us-0.22-lgraph has 368k words but the compile package's
en.dic only has 312k. This script generates pronunciations for the ~56k
missing words using Phonetisaurus G2P (trained on the same dictionary format).

IMPORTANT: Uses Phonetisaurus (not espeak-ng) because:
- Phonetisaurus G2P model was trained on en.dic data
- Produces compatible phoneme format (V, 3`, etc.)
- espeak-ng produces different format (@, schwa handling) that's incompatible

Usage:
    ./generate_missing_pronunciations.py [--compile COMPILE_DIR] [--output FILE]

Requirements:
    pip install phonetisaurus
"""

import sys
import os
import argparse
from pathlib import Path

try:
    import phonetisaurus
except ImportError:
    print("ERROR: phonetisaurus not installed", file=sys.stderr)
    print("Install with: pip install --break-system-packages phonetisaurus", file=sys.stderr)
    sys.exit(1)


def load_lgraph_words(model_path):
    """Load words from lgraph words.txt."""
    words_file = Path(model_path) / 'graph' / 'words.txt'
    words = set()
    with open(words_file, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if parts:
                word = parts[0].lower()
                # Skip special tokens
                if not word.startswith('<') and not word.startswith('#'):
                    words.add(word)
    return words


def load_en_dic_words(compile_path):
    """Load words from en.dic."""
    dic_file = Path(compile_path) / 'db' / 'en.dic'
    words = set()
    with open(dic_file, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if parts:
                words.add(parts[0].lower())
    return words


def parse_args():
    parser = argparse.ArgumentParser(
        description='Generate pronunciations for words missing from en.dic')
    parser.add_argument('--model', '-m',
        default=os.path.expanduser('~/Downloads/vosk-model-en-us-0.22-lgraph'),
        help='lgraph model directory')
    parser.add_argument('--compile', '-c',
        default=os.path.expanduser('~/Downloads/vosk-model-en-us-0.22-compile'),
        help='Compile package directory')
    parser.add_argument('--output', '-o',
        default='base_missing.dic',
        help='Output dictionary file')
    parser.add_argument('--batch-size', '-b', type=int, default=5000,
        help='Progress reporting batch size')
    return parser.parse_args()


def main():
    args = parse_args()

    # G2P model path
    g2p_model = Path(args.compile) / 'db' / 'en-g2p' / 'en.fst'
    if not g2p_model.exists():
        print(f"ERROR: G2P model not found: {g2p_model}", file=sys.stderr)
        sys.exit(1)

    print(f"Loading lgraph words from {args.model}...", file=sys.stderr)
    lgraph_words = load_lgraph_words(args.model)
    print(f"  Found {len(lgraph_words):,} words", file=sys.stderr)

    print(f"Loading en.dic words from {args.compile}...", file=sys.stderr)
    endic_words = load_en_dic_words(args.compile)
    print(f"  Found {len(endic_words):,} words", file=sys.stderr)

    # Find missing words
    missing = lgraph_words - endic_words
    print(f"\nMissing pronunciations: {len(missing):,} words", file=sys.stderr)

    if not missing:
        print("No missing words - nothing to generate", file=sys.stderr)
        return

    # Generate pronunciations using Phonetisaurus
    print(f"Generating pronunciations using Phonetisaurus...", file=sys.stderr)
    print(f"G2P model: {g2p_model}", file=sys.stderr)

    sorted_missing = sorted(missing)
    total = len(sorted_missing)
    pronunciations = {}

    # Process in batches for progress reporting
    batch_size = args.batch_size
    for batch_start in range(0, total, batch_size):
        batch_end = min(batch_start + batch_size, total)
        batch = sorted_missing[batch_start:batch_end]

        for word, phones in phonetisaurus.predict(batch, str(g2p_model)):
            pron = ' '.join(phones)
            if pron:
                pronunciations[word] = pron

        print(f"  Progress: {batch_end:,}/{total:,} ({100*batch_end//total}%)", file=sys.stderr)

    print(f"\nGenerated {len(pronunciations):,} pronunciations", file=sys.stderr)

    failed = set(missing) - set(pronunciations.keys())
    if failed:
        print(f"Failed for {len(failed):,} words", file=sys.stderr)

    # Write output
    output_path = Path(args.output)
    with open(output_path, 'w') as f:
        for word, pron in sorted(pronunciations.items()):
            f.write(f"{word} {pron}\n")

    print(f"\nWrote {output_path} ({len(pronunciations):,} entries)", file=sys.stderr)

    # Write failed words if any
    if failed:
        failed_path = output_path.with_suffix('.failed')
        with open(failed_path, 'w') as f:
            for word in sorted(failed):
                f.write(f"{word}\n")
        print(f"Wrote {failed_path} ({len(failed):,} entries)", file=sys.stderr)


if __name__ == "__main__":
    main()
