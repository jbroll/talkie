#!/usr/bin/env python3
"""
Extract words from markdown files that are not in the Vosk vocabulary.
Outputs missing words and their context sentences for LM training.

Usage:
    ./extract_vocabulary.py /path/to/search [/more/paths...]

Outputs:
    missing_words.txt   - Words not in vocabulary (need pronunciations)
    extra_contexts.txt  - Sentences containing missing words (for LM)
    extra.dic           - Dictionary with pronunciations (for Vosk compile)

Requirements:
    phonetisaurus       - For G2P pronunciation generation
                          Install: pip install phonetisaurus
"""

import sys
import re
import os
import subprocess
from pathlib import Path
from collections import defaultdict

try:
    import phonetisaurus
    HAVE_PHONETISAURUS = True
except ImportError:
    HAVE_PHONETISAURUS = False

# Configuration
VOCAB_PATH = os.path.expanduser("~/Downloads/vosk-model-en-us-0.22-lgraph/graph/words.txt")
G2P_MODEL = os.path.expanduser("~/Downloads/vosk-model-en-us-0.22-compile/db/en-g2p/en.fst")
MIN_WORD_LENGTH = 2
MIN_OCCURRENCES = 1  # Minimum times a word must appear to be included


def generate_pronunciations_batch(words, g2p_model=None):
    """Generate Vosk-format pronunciations for a batch of words using Phonetisaurus."""
    if not HAVE_PHONETISAURUS:
        print("ERROR: phonetisaurus not installed", file=sys.stderr)
        print("Install with: pip install phonetisaurus", file=sys.stderr)
        return {}

    if g2p_model is None:
        g2p_model = G2P_MODEL

    if not os.path.exists(g2p_model):
        print(f"ERROR: G2P model not found: {g2p_model}", file=sys.stderr)
        return {}

    pronunciations = {}
    for word, phones in phonetisaurus.predict(list(words), g2p_model):
        pron = ' '.join(phones)
        if pron:
            pronunciations[word] = pron
    return pronunciations


def generate_pronunciation(word, g2p_model=None):
    """Generate Vosk-format pronunciation for a single word."""
    result = generate_pronunciations_batch([word], g2p_model)
    return result.get(word)

def load_vocabulary(vocab_path):
    """Load Vosk vocabulary into a set."""
    vocab = set()
    with open(vocab_path, 'r') as f:
        for line in f:
            word = line.split()[0].lower()
            vocab.add(word)
    return vocab

def extract_words(text):
    """Extract lowercase words from text."""
    # Match words (including contractions and hyphenated words)
    words = re.findall(r"[a-zA-Z][a-zA-Z'-]*[a-zA-Z]|[a-zA-Z]", text)
    return [w.lower() for w in words]

def extract_sentences(text):
    """Split text into sentences."""
    # Simple sentence splitting on . ! ? followed by space or newline
    sentences = re.split(r'(?<=[.!?])\s+|\n\n+', text)
    return [s.strip() for s in sentences if s.strip()]

def find_git_root(path):
    """Find the git root directory for a path."""
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--show-toplevel'],
            cwd=path,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except:
        pass
    return None

def find_git_repos(path):
    """Find all git repositories under a path."""
    repos = []
    p = Path(path).resolve()

    # Check if path itself is a git repo
    if (p / '.git').exists():
        repos.append(p)

    # Find nested git repos
    for git_dir in p.rglob('.git'):
        if git_dir.is_dir():
            repos.append(git_dir.parent)

    return repos

def find_markdown_files(paths):
    """Find markdown files respecting .gitignore patterns."""
    md_files = []
    seen_repos = set()

    for path in paths:
        p = Path(path).resolve()

        if p.is_file() and p.suffix.lower() == '.md':
            md_files.append(p)
            continue

        if not p.is_dir():
            continue

        # Find all git repos under this path
        repos = find_git_repos(p)

        for repo in repos:
            if repo in seen_repos:
                continue
            seen_repos.add(repo)

            # Use git ls-files to get tracked files (respects .gitignore)
            try:
                result = subprocess.run(
                    ['git', 'ls-files', '*.md'],
                    cwd=repo,
                    capture_output=True,
                    text=True
                )
                if result.returncode == 0:
                    for line in result.stdout.strip().split('\n'):
                        if line:
                            md_files.append(repo / line)
            except:
                pass

        # If no git repos found, fallback to glob
        if not repos:
            md_files.extend(p.rglob("*.md"))

    return list(set(md_files))  # Deduplicate

def strip_code_blocks(text):
    """Remove fenced code blocks and inline code from markdown."""
    # Remove fenced code blocks (```...``` or ~~~...~~~)
    text = re.sub(r'```[\s\S]*?```', ' ', text)
    text = re.sub(r'~~~[\s\S]*?~~~', ' ', text)
    # Remove indented code blocks (4+ spaces at start of line)
    text = re.sub(r'^(?:    |\t).*$', ' ', text, flags=re.MULTILINE)
    # Remove inline code (`...`)
    text = re.sub(r'`[^`]+`', ' ', text)
    return text


def process_files(md_files, vocab):
    """Process markdown files and find missing words with contexts."""
    missing_words = defaultdict(int)  # word -> count
    word_contexts = defaultdict(set)  # word -> set of context sentences

    for md_file in md_files:
        try:
            text = md_file.read_text(encoding='utf-8', errors='ignore')
        except Exception as e:
            print(f"Warning: Could not read {md_file}: {e}", file=sys.stderr)
            continue

        # Strip code blocks before extracting words
        text = strip_code_blocks(text)

        # Extract all words to count occurrences
        words = extract_words(text)
        for word in words:
            if len(word) >= MIN_WORD_LENGTH and word not in vocab:
                missing_words[word] += 1

        # Extract sentences for context
        sentences = extract_sentences(text)
        for sentence in sentences:
            sentence_words = set(extract_words(sentence))
            for word in sentence_words:
                if len(word) >= MIN_WORD_LENGTH and word not in vocab:
                    # Clean up the sentence for LM training
                    clean = clean_sentence(sentence)
                    if clean and len(clean.split()) >= 3:
                        word_contexts[word].add(clean)

    return missing_words, word_contexts

def clean_sentence(sentence):
    """Clean sentence for language model training."""
    # Remove markdown formatting
    s = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', sentence)  # [text](url) -> text
    s = re.sub(r'[`*_~#]', '', s)  # Remove markdown chars
    s = re.sub(r'\\(.)', r'\1', s)  # Remove backslash escapes (e.g., \. -> .)
    s = re.sub(r'\s+', ' ', s)  # Normalize whitespace
    s = s.strip()

    # Skip if too short or looks like code
    if len(s) < 10:
        return None
    if re.search(r'[{}()\[\]=<>]', s):  # Likely code
        return None

    return s

def is_noise_word(word):
    """Check if a word looks like noise (code identifier, path, etc.)."""
    # Too long - likely concatenated identifier
    if len(word) > 20:
        return True
    # Multiple hyphens - likely a path or model name
    if word.count('-') >= 2:
        return True
    # Looks like a code identifier (camelCase or has underscores)
    if '_' in word:
        return True
    if re.search(r'[a-z][A-Z]', word):  # camelCase
        return True
    # Contains digits mixed with letters (version numbers, etc.)
    if re.search(r'\d', word) and re.search(r'[a-zA-Z]', word):
        return True
    return False


def parse_args():
    """Parse command line arguments."""
    import argparse
    parser = argparse.ArgumentParser(
        description='Extract missing vocabulary from corpus for Vosk model')
    parser.add_argument('corpus', nargs='+', help='Directories to scan for .md/.txt files')
    parser.add_argument('--model', '-m', default=os.path.expanduser(
        '~/Downloads/vosk-model-en-us-0.22-lgraph'),
        help='Base Vosk model directory (default: ~/Downloads/vosk-model-en-us-0.22-lgraph)')
    parser.add_argument('--output', '-o', default='.',
        help='Output directory for generated files (default: current directory)')
    parser.add_argument('--top', '-n', type=int, default=500,
        help='Generate pronunciations for top N words (default: 500)')
    parser.add_argument('--min-occurrences', type=int, default=3,
        help='Minimum word occurrences to include (default: 3)')
    parser.add_argument('--max-length', type=int, default=20,
        help='Maximum word length (default: 20)')
    parser.add_argument('--max-hyphens', type=int, default=1,
        help='Maximum hyphens in word (default: 1, use 0 to exclude all)')
    parser.add_argument('--no-filter', action='store_true',
        help='Disable noise filtering (code identifiers, paths, etc.)')
    return parser.parse_args()

def main():
    args = parse_args()

    search_paths = args.corpus
    vocab_path = os.path.join(args.model, 'graph/words.txt')
    output_dir = Path(args.output)
    top_words = args.top

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading vocabulary from {vocab_path}...", file=sys.stderr)
    vocab = load_vocabulary(vocab_path)
    print(f"Loaded {len(vocab):,} words", file=sys.stderr)

    print(f"Finding markdown files...", file=sys.stderr)
    md_files = find_markdown_files(search_paths)
    print(f"Found {len(md_files)} markdown files", file=sys.stderr)

    print(f"Processing files...", file=sys.stderr)
    missing_words, word_contexts = process_files(md_files, vocab)

    # Apply filters
    print(f"Filtering words...", file=sys.stderr)
    print(f"  Raw missing words: {len(missing_words)}", file=sys.stderr)

    filtered_words = {}
    filtered_out = {'min_occ': 0, 'max_len': 0, 'max_hyph': 0, 'noise': 0}

    for word, count in missing_words.items():
        # Minimum occurrences
        if count < args.min_occurrences:
            filtered_out['min_occ'] += 1
            continue
        # Maximum length
        if len(word) > args.max_length:
            filtered_out['max_len'] += 1
            continue
        # Maximum hyphens
        if word.count('-') > args.max_hyphens:
            filtered_out['max_hyph'] += 1
            continue
        # Noise filter (unless disabled)
        if not args.no_filter and is_noise_word(word):
            filtered_out['noise'] += 1
            continue
        filtered_words[word] = count

    print(f"  After filtering: {len(filtered_words)}", file=sys.stderr)
    print(f"  Filtered out: {filtered_out}", file=sys.stderr)

    # Sort by frequency
    sorted_words = sorted(filtered_words.items(), key=lambda x: -x[1])

    # Output missing words summary
    print(f"\n=== Missing Words ({len(sorted_words)} unique) ===\n")
    print(f"{'Word':<30} {'Count':<10} {'Pronunciation'}")
    print("-" * 70)

    # Generate pronunciations for top words using batch API
    print(f"Generating pronunciations for top {top_words} words...", file=sys.stderr)
    words_to_pronounce = [word for word, count in sorted_words[:top_words]]
    g2p_model = os.path.join(args.model.replace('lgraph', 'compile'), 'db/en-g2p/en.fst')
    if not os.path.exists(g2p_model):
        g2p_model = G2P_MODEL  # Fall back to default
    pronunciations = generate_pronunciations_batch(words_to_pronounce, g2p_model)

    # Display first 50
    for i, (word, count) in enumerate(sorted_words[:top_words]):
        pron = pronunciations.get(word)
        if i < 50:
            pron_display = pron if pron else "(no pronunciation)"
            print(f"{word:<30} {count:<10} {pron_display}")
        elif i == 50:
            print(f"...")

    if len(sorted_words) > top_words:
        print(f"\n... and {len(sorted_words) - top_words} more words (use TOP_WORDS=N to increase)")

    # Write output files
    missing_file = output_dir / 'missing_words.txt'
    with open(missing_file, 'w') as f:
        for word, count in sorted_words:
            f.write(f"{word}\t{count}\n")
    print(f"\nWrote {missing_file} ({len(sorted_words)} words)", file=sys.stderr)

    # Write context sentences
    context_file = output_dir / 'extra_contexts.txt'
    seen = set()
    with open(context_file, 'w') as f:
        for word, count in sorted_words:
            for ctx in word_contexts.get(word, []):
                if ctx not in seen:
                    f.write(ctx + "\n")
                    seen.add(ctx)
    print(f"Wrote {context_file} ({len(seen)} sentences)", file=sys.stderr)

    # Write dictionary with pronunciations (Vosk format)
    dic_file = output_dir / 'extra.dic'
    with open(dic_file, 'w') as f:
        for word, pron in sorted(pronunciations.items()):
            f.write(f"{word} {pron}\n")
    print(f"Wrote {dic_file} ({len(pronunciations)} pronunciations)", file=sys.stderr)

    # Summary
    print(f"\n=== Summary ===", file=sys.stderr)
    print(f"  Missing words found: {len(sorted_words)}", file=sys.stderr)
    print(f"  Pronunciations generated: {len(pronunciations)}", file=sys.stderr)
    print(f"  Context sentences: {len(seen)}", file=sys.stderr)
    print(f"\nOutput files in: {output_dir}", file=sys.stderr)

if __name__ == "__main__":
    main()
