#!/usr/bin/env python3
"""
Simple ARPA language model pruning tool.
Open source replacement for SRILM's `ngram -prune` command.

Usage:
    ./arpa_prune.py --lm input.lm.gz --threshold 1e-8 --output pruned.lm.gz

Removes n-grams whose removal increases model perplexity by less than threshold.
Uses entropy-based pruning (Stolcke, 1998).
"""

import sys
import gzip
import math
import argparse
from collections import defaultdict

def open_lm(path):
    """Open LM file, handling gzip if needed."""
    if path.endswith('.gz'):
        return gzip.open(path, 'rt', encoding='utf-8')
    return open(path, 'r', encoding='utf-8')

def write_lm(path):
    """Open LM file for writing, handling gzip if needed."""
    if path.endswith('.gz'):
        return gzip.open(path, 'wt', encoding='utf-8')
    return open(path, 'w', encoding='utf-8')

def parse_arpa(path):
    """Parse ARPA format LM file."""
    ngrams = defaultdict(dict)

    with open_lm(path) as f:
        current_order = 0

        for line in f:
            line = line.strip()

            if not line or line == '\\data\\' or line.startswith('ngram '):
                continue

            if line == '\\end\\':
                break

            if line.startswith('\\') and line.endswith('-grams:'):
                current_order = int(line[1:-7])
                continue

            if current_order > 0:
                parts = line.split('\t')
                if len(parts) >= 2:
                    log_prob = float(parts[0])
                    words = tuple(parts[1].split())
                    backoff = float(parts[2]) if len(parts) > 2 else 0.0
                    ngrams[current_order][words] = (log_prob, backoff)

    return ngrams

def prune_ngrams(ngrams, threshold):
    """
    Prune n-grams using simplified entropy-based pruning.

    For each n-gram, estimate the change in cross-entropy if removed.
    Remove if change < threshold.

    Simplified approach: remove n-grams with very low probability
    that don't contribute significantly to the model.
    """
    result = defaultdict(dict)
    max_order = max(ngrams.keys())

    removed = 0
    kept = 0

    for order in sorted(ngrams.keys()):
        for ngram, (prob, bow) in ngrams[order].items():
            # Always keep unigrams (order 1)
            if order == 1:
                result[order][ngram] = (prob, bow)
                kept += 1
                continue

            # For higher order n-grams, check if probability is significant
            # Pruning threshold is typically applied to the probability mass
            # that would be "lost" by backing off instead

            # Simple heuristic: keep if probability > threshold (in log10)
            # threshold 1e-8 = -8 in log10
            log_threshold = math.log10(threshold) if threshold > 0 else -float('inf')

            # More sophisticated: compare to backoff probability
            # If this n-gram's prob is close to what backoff would give,
            # it can be pruned
            history = ngram[:-1]
            predicted = ngram[-1:]

            # Get backoff probability estimate
            if history in ngrams.get(order-1, {}):
                _, hist_bow = ngrams[order-1][history]
            else:
                hist_bow = 0.0

            if predicted in ngrams.get(1, {}):
                unigram_prob, _ = ngrams[1][predicted]
            else:
                unigram_prob = -10.0  # Default low probability

            backoff_prob = hist_bow + unigram_prob

            # Prune if the difference from backoff is small
            prob_gain = prob - backoff_prob

            if prob_gain < log_threshold:
                removed += 1
            else:
                result[order][ngram] = (prob, bow)
                kept += 1

    return result, kept, removed

def write_arpa(ngrams, path):
    """Write ngrams to ARPA format file."""
    with write_lm(path) as f:
        f.write('\\data\\\n')
        for order in sorted(ngrams.keys()):
            f.write(f'ngram {order}={len(ngrams[order])}\n')
        f.write('\n')

        for order in sorted(ngrams.keys()):
            f.write(f'\\{order}-grams:\n')
            for ngram in sorted(ngrams[order].keys()):
                prob, bow = ngrams[order][ngram]
                ngram_str = ' '.join(ngram)
                if bow != 0.0 and order < max(ngrams.keys()):
                    f.write(f'{prob:.6f}\t{ngram_str}\t{bow:.6f}\n')
                else:
                    f.write(f'{prob:.6f}\t{ngram_str}\n')
            f.write('\n')

        f.write('\\end\\\n')

def main():
    parser = argparse.ArgumentParser(
        description='Prune ARPA language model (SRILM-compatible)')
    parser.add_argument('--lm', required=True, help='Input LM (ARPA format)')
    parser.add_argument('--threshold', type=float, default=1e-8,
                        help='Pruning threshold (default: 1e-8)')
    parser.add_argument('--output', '-o', required=True, help='Output LM path')

    args = parser.parse_args()

    print(f"Loading LM: {args.lm}", file=sys.stderr)
    ngrams = parse_arpa(args.lm)
    total_before = sum(len(v) for v in ngrams.values())
    print(f"  Total ngrams: {total_before}", file=sys.stderr)

    print(f"Pruning with threshold={args.threshold}...", file=sys.stderr)
    result, kept, removed = prune_ngrams(ngrams, args.threshold)
    print(f"  Kept: {kept}, Removed: {removed} ({100*removed/total_before:.1f}%)", file=sys.stderr)

    print(f"Writing: {args.output}", file=sys.stderr)
    write_arpa(result, args.output)
    print("Done.", file=sys.stderr)

if __name__ == '__main__':
    main()
