#!/usr/bin/env python3
"""
Simple ARPA language model interpolation tool.
Open source replacement for SRILM's `ngram -mix-lm` command.

Usage:
    ./arpa_interpolate.py --lm base.lm.gz --mix-lm extra.lm.gz --lambda 0.95 --output mixed.lm.gz

This performs linear interpolation:
    P_mixed(w|h) = lambda * P_base(w|h) + (1-lambda) * P_extra(w|h)
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
    """Parse ARPA format LM file into a dictionary structure."""
    ngrams = defaultdict(dict)  # order -> {ngram_tuple: (log_prob, backoff)}

    with open_lm(path) as f:
        current_order = 0
        in_data = False

        for line in f:
            line = line.strip()

            if not line:
                continue

            if line == '\\data\\':
                in_data = True
                continue

            if line == '\\end\\':
                break

            if line.startswith('\\') and line.endswith('-grams:'):
                current_order = int(line[1:-7])
                continue

            if line.startswith('ngram '):
                continue  # Skip count lines

            if current_order > 0:
                parts = line.split('\t')
                if len(parts) >= 2:
                    log_prob = float(parts[0])
                    words = tuple(parts[1].split())
                    backoff = float(parts[2]) if len(parts) > 2 else 0.0
                    ngrams[current_order][words] = (log_prob, backoff)

    return ngrams

def log_add(log_a, log_b):
    """Add two log probabilities: log(10^a + 10^b)."""
    if log_a == float('-inf'):
        return log_b
    if log_b == float('-inf'):
        return log_a
    if log_a > log_b:
        return log_a + math.log10(1 + 10**(log_b - log_a))
    else:
        return log_b + math.log10(1 + 10**(log_a - log_b))

def interpolate(lm1, lm2, lambda1):
    """Interpolate two LMs with weight lambda1 for lm1."""
    lambda2 = 1.0 - lambda1
    log_lambda1 = math.log10(lambda1) if lambda1 > 0 else float('-inf')
    log_lambda2 = math.log10(lambda2) if lambda2 > 0 else float('-inf')

    result = defaultdict(dict)

    # Get all orders present in either LM
    all_orders = set(lm1.keys()) | set(lm2.keys())

    for order in all_orders:
        # Get all ngrams at this order from both LMs
        all_ngrams = set(lm1.get(order, {}).keys()) | set(lm2.get(order, {}).keys())

        for ngram in all_ngrams:
            prob1, bow1 = lm1.get(order, {}).get(ngram, (float('-inf'), 0.0))
            prob2, bow2 = lm2.get(order, {}).get(ngram, (float('-inf'), 0.0))

            # Interpolate probabilities: lambda1 * P1 + lambda2 * P2
            # In log space: log(lambda1 * 10^p1 + lambda2 * 10^p2)
            if prob1 != float('-inf') and prob2 != float('-inf'):
                interp_prob = log_add(log_lambda1 + prob1, log_lambda2 + prob2)
            elif prob1 != float('-inf'):
                interp_prob = log_lambda1 + prob1
            elif prob2 != float('-inf'):
                interp_prob = log_lambda2 + prob2
            else:
                continue  # Skip if neither has this ngram

            # For backoff, use weighted average (simplified)
            # In practice, backoff weights need recalculation for proper normalization
            # This is an approximation
            if bow1 != 0.0 or bow2 != 0.0:
                interp_bow = lambda1 * bow1 + lambda2 * bow2
            else:
                interp_bow = 0.0

            result[order][ngram] = (interp_prob, interp_bow)

    return result

def write_arpa(ngrams, path):
    """Write ngrams to ARPA format file."""
    with write_lm(path) as f:
        # Header
        f.write('\\data\\\n')
        for order in sorted(ngrams.keys()):
            f.write(f'ngram {order}={len(ngrams[order])}\n')
        f.write('\n')

        # N-grams
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
        description='Interpolate two ARPA language models (SRILM-compatible)')
    parser.add_argument('--lm', required=True, help='Primary LM (ARPA format)')
    parser.add_argument('--mix-lm', required=True, help='LM to mix in (ARPA format)')
    parser.add_argument('--lambda', dest='lambda_weight', type=float, default=0.9,
                        help='Weight for primary LM (default: 0.9)')
    parser.add_argument('--output', '-o', required=True, help='Output LM path')

    args = parser.parse_args()

    print(f"Loading primary LM: {args.lm}", file=sys.stderr)
    lm1 = parse_arpa(args.lm)
    print(f"  Orders: {sorted(lm1.keys())}, Total ngrams: {sum(len(v) for v in lm1.values())}", file=sys.stderr)

    print(f"Loading mix LM: {args.mix_lm}", file=sys.stderr)
    lm2 = parse_arpa(args.mix_lm)
    print(f"  Orders: {sorted(lm2.keys())}, Total ngrams: {sum(len(v) for v in lm2.values())}", file=sys.stderr)

    print(f"Interpolating with lambda={args.lambda_weight}...", file=sys.stderr)
    result = interpolate(lm1, lm2, args.lambda_weight)
    print(f"  Result: {sum(len(v) for v in result.values())} ngrams", file=sys.stderr)

    print(f"Writing: {args.output}", file=sys.stderr)
    write_arpa(result, args.output)
    print("Done.", file=sys.stderr)

if __name__ == '__main__':
    main()
