#!/usr/bin/env python3
"""
Vosk Model Builder

Builds a custom Vosk model by:
1. Copying a base model (lgraph format)
2. Scanning corpus directories for new vocabulary
3. Generating pronunciations for new words
4. Building custom language model
5. Producing final model artifacts

Usage:
    ./build_model.py --base-model ~/Downloads/vosk-model-en-us-0.22-lgraph \
                     --corpus ~/src ~/docs \
                     --output ~/models/vosk-custom

Requirements:
    - espeak-ng (for G2P)
    - Kaldi compile package (for graph building)
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from extract_vocabulary import (
    load_vocabulary,
    find_markdown_files,
    process_files,
    generate_pronunciation,
    VOCAB_PATH,
)
from arpa_interpolate import parse_arpa, interpolate, write_arpa
from arpa_prune import prune_ngrams

class ModelBuilder:
    def __init__(self, base_model, corpus_paths, output_dir, compile_pkg=None):
        self.base_model = Path(base_model)
        self.corpus_paths = [Path(p) for p in corpus_paths]
        self.output_dir = Path(output_dir)
        self.compile_pkg = Path(compile_pkg) if compile_pkg else None

        # Build directories
        self.build_dir = self.output_dir / "build"
        self.corpus_dir = self.build_dir / "corpus"
        self.dict_dir = self.build_dir / "dict"
        self.lm_dir = self.build_dir / "lm"
        self.model_dir = self.output_dir / "model"

    def log(self, msg):
        print(f"[build] {msg}", file=sys.stderr)

    def run(self, cmd, cwd=None):
        """Run a shell command."""
        self.log(f"Running: {' '.join(cmd)}")
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error: {result.stderr}", file=sys.stderr)
            raise RuntimeError(f"Command failed: {' '.join(cmd)}")
        return result.stdout

    def setup_directories(self):
        """Create build directory structure."""
        self.log("Setting up directories...")

        for d in [self.build_dir, self.corpus_dir, self.dict_dir, self.lm_dir]:
            d.mkdir(parents=True, exist_ok=True)

        # Copy base model to output
        if self.model_dir.exists():
            shutil.rmtree(self.model_dir)
        self.log(f"Copying base model from {self.base_model}")
        shutil.copytree(self.base_model, self.model_dir)

    def scan_corpus(self):
        """Scan corpus for missing vocabulary."""
        self.log("Scanning corpus for vocabulary...")

        # Load existing vocabulary
        vocab_path = self.model_dir / "graph" / "words.txt"
        vocab = load_vocabulary(vocab_path)
        self.log(f"Base vocabulary: {len(vocab):,} words")

        # Find markdown files
        md_files = find_markdown_files(self.corpus_paths)
        self.log(f"Found {len(md_files)} markdown files")

        # Process files
        missing_words, word_contexts = process_files(md_files, vocab)

        # Filter by minimum occurrences
        min_occurrences = 2
        filtered = {w: c for w, c in missing_words.items() if c >= min_occurrences}
        sorted_words = sorted(filtered.items(), key=lambda x: -x[1])

        self.log(f"Found {len(sorted_words)} missing words (min {min_occurrences} occurrences)")

        # Save word list
        words_file = self.corpus_dir / "missing_words.txt"
        with open(words_file, 'w') as f:
            for word, count in sorted_words:
                f.write(f"{word}\t{count}\n")

        # Save context sentences
        contexts_file = self.corpus_dir / "contexts.txt"
        seen = set()
        with open(contexts_file, 'w') as f:
            for word, _ in sorted_words:
                for ctx in word_contexts.get(word, []):
                    if ctx not in seen:
                        f.write(ctx + "\n")
                        seen.add(ctx)
        self.log(f"Saved {len(seen)} context sentences")

        return sorted_words, word_contexts

    def generate_pronunciations(self, words, max_words=1000):
        """Generate pronunciations for new words."""
        self.log(f"Generating pronunciations for top {max_words} words...")

        pronunciations = {}
        for i, (word, count) in enumerate(words[:max_words]):
            pron = generate_pronunciation(word)
            if pron:
                pronunciations[word] = pron
            if (i + 1) % 100 == 0:
                self.log(f"  Processed {i+1}/{min(len(words), max_words)} words...")

        self.log(f"Generated {len(pronunciations)} pronunciations")

        # Save dictionary
        dict_file = self.dict_dir / "extra.dic"
        with open(dict_file, 'w') as f:
            for word, pron in sorted(pronunciations.items()):
                f.write(f"{word} {pron}\n")

        return pronunciations

    def build_language_model(self, base_lm_path=None, lambda_weight=0.95):
        """Build interpolated language model."""
        self.log("Building language model...")

        contexts_file = self.corpus_dir / "contexts.txt"
        if not contexts_file.exists() or contexts_file.stat().st_size == 0:
            self.log("No context sentences, skipping LM build")
            return None

        # Build LM from corpus using Kaldi's tool
        extra_lm = self.lm_dir / "extra.lm"

        if self.compile_pkg:
            make_lm = self.compile_pkg / "utils" / "lang" / "make_kn_lm.py"
            if make_lm.exists():
                self.run([
                    "python3", str(make_lm),
                    "-ngram-order", "3",
                    "-text", str(contexts_file),
                    "-lm", str(extra_lm)
                ])
            else:
                self.log("Warning: make_kn_lm.py not found, skipping LM build")
                return None
        else:
            self.log("Warning: No compile package specified, skipping LM build")
            return None

        # Interpolate with base LM if provided
        if base_lm_path and Path(base_lm_path).exists():
            self.log(f"Interpolating with base LM (lambda={lambda_weight})...")

            base_lm = parse_arpa(base_lm_path)
            extra = parse_arpa(str(extra_lm))
            mixed = interpolate(base_lm, extra, lambda_weight)

            mixed_lm = self.lm_dir / "mixed.lm"
            write_arpa(mixed, str(mixed_lm))

            # Prune
            self.log("Pruning language model...")
            pruned, kept, removed = prune_ngrams(mixed, threshold=1e-8)

            final_lm = self.lm_dir / "final.lm"
            write_arpa(pruned, str(final_lm))
            self.log(f"Final LM: {kept} n-grams (removed {removed})")

            return final_lm
        else:
            return extra_lm

    def add_words_to_vocab(self, pronunciations):
        """Add new words to words.txt vocabulary file."""
        words_file = self.model_dir / "graph" / "words.txt"

        # Read existing vocabulary
        existing = {}
        max_id = 0
        with open(words_file, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    word, word_id = parts[0], int(parts[1])
                    existing[word] = word_id
                    max_id = max(max_id, word_id)

        # Add new words
        added = 0
        with open(words_file, 'a') as f:
            for word in sorted(pronunciations.keys()):
                if word not in existing:
                    max_id += 1
                    f.write(f"{word} {max_id}\n")
                    added += 1

        self.log(f"Added {added} new words to words.txt (max_id now {max_id})")
        return added

    def build_graph(self, pronunciations):
        """Build Vosk graph using our tools."""
        self.log("Building graph...")

        # Step 1: Add new words to vocabulary
        self.add_words_to_vocab(pronunciations)

        # Step 2: Build language model
        contexts_file = self.corpus_dir / "contexts.txt"
        if not contexts_file.exists() or contexts_file.stat().st_size == 0:
            self.log("No context sentences, skipping graph build")
            return False

        extra_lm = self.lm_dir / "extra.lm"

        # Use make_kn_lm.py if compile package available
        if self.compile_pkg:
            make_lm = self.compile_pkg / "utils" / "lang" / "make_kn_lm.py"
            if make_lm.exists():
                self.log("Building n-gram LM from contexts...")
                self.run([
                    "python3", str(make_lm),
                    "-ngram-order", "3",
                    "-text", str(contexts_file),
                    "-lm", str(extra_lm)
                ])
            else:
                self.log("Warning: make_kn_lm.py not found")
                return False
        else:
            self.log("Warning: No compile package, cannot build LM")
            return False

        # Step 3: Convert ARPA to FST using kaldilm
        self.log("Converting ARPA to FST...")
        words_txt = self.model_dir / "graph" / "words.txt"
        gr_fst = self.lm_dir / "Gr.fst"
        new_words_txt = self.lm_dir / "words.txt"

        try:
            from kaldilm import arpa2fst
            # Don't read existing symbol table (has bug: <s> and </s> same ID)
            # Let arpa2fst create new symbol table
            arpa2fst(
                str(extra_lm),
                output_fst=str(gr_fst),
                disambig_symbol="#0",
                write_symbol_table=str(new_words_txt)
            )
            self.log(f"Created {gr_fst}")
        except ImportError:
            self.log("Error: kaldilm not installed. Run: pip install kaldilm")
            return False
        except Exception as e:
            self.log(f"Error converting ARPA to FST: {e}")
            return False

        # Step 4: Process with OpenFST tools
        fst_bin = Path.home() / "src" / "fst-tools" / "install" / "bin"
        fst_lib = Path.home() / "src" / "fst-tools" / "install" / "lib"

        if not fst_bin.exists():
            self.log(f"Warning: OpenFST tools not found at {fst_bin}")
            self.log("Gr.fst created but not optimized")
        else:
            env = os.environ.copy()
            env["LD_LIBRARY_PATH"] = f"{fst_lib}:{env.get('LD_LIBRARY_PATH', '')}"

            # Sort arcs for efficient composition
            gr_sorted = self.lm_dir / "Gr_sorted.fst"
            self.log("Sorting FST arcs...")
            result = subprocess.run(
                [str(fst_bin / "fstarcsort"), "--sort_type=ilabel",
                 str(gr_fst), str(gr_sorted)],
                env=env, capture_output=True, text=True
            )
            if result.returncode == 0:
                shutil.move(str(gr_sorted), str(gr_fst))
                self.log("FST arc-sorted successfully")
            else:
                self.log(f"Warning: fstarcsort failed: {result.stderr}")

            # Get FST info
            result = subprocess.run(
                [str(fst_bin / "fstinfo"), str(gr_fst)],
                env=env, capture_output=True, text=True
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n')[:8]:
                    if line.strip():
                        self.log(f"  {line}")

        # Step 5: Copy Gr.fst to model (backup original first)
        model_gr = self.model_dir / "graph" / "Gr.fst"
        model_gr_backup = self.model_dir / "graph" / "Gr.fst.orig"

        if model_gr.exists() and not model_gr_backup.exists():
            shutil.copy(model_gr, model_gr_backup)
            self.log(f"Backed up original Gr.fst to {model_gr_backup.name}")

        shutil.copy(gr_fst, model_gr)
        self.log(f"Installed new Gr.fst to model")

        # Note about limitations
        self.log("")
        self.log("NOTE: New words added to vocabulary and language model.")
        self.log("However, HCLr.fst (lexicon) was not rebuilt.")
        self.log("New words may not be recognized until HCLr.fst is rebuilt")
        self.log("with Kaldi tools (requires full Kaldi installation).")

        return True

    def save_manifest(self, words, pronunciations):
        """Save build manifest for reproducibility."""
        manifest = {
            "base_model": str(self.base_model),
            "corpus_paths": [str(p) for p in self.corpus_paths],
            "words_added": len(pronunciations),
            "total_words_found": len(words),
        }

        manifest_file = self.output_dir / "manifest.json"
        with open(manifest_file, 'w') as f:
            json.dump(manifest, f, indent=2)
        self.log(f"Saved manifest to {manifest_file}")

    def build(self):
        """Run full build pipeline."""
        self.log("=" * 60)
        self.log("Vosk Model Builder")
        self.log("=" * 60)

        # Step 1: Setup
        self.setup_directories()

        # Step 2: Scan corpus
        words, contexts = self.scan_corpus()

        if not words:
            self.log("No new words found, nothing to do")
            return

        # Step 3: Generate pronunciations
        pronunciations = self.generate_pronunciations(words)

        # Step 4: Build graph (LM + FST)
        self.build_graph(pronunciations)

        # Step 5: Save manifest
        self.save_manifest(words, pronunciations)

        self.log("=" * 60)
        self.log("Build complete!")
        self.log(f"Output: {self.output_dir}")
        self.log("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Build custom Vosk model with domain vocabulary",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Basic usage
    ./build_model.py --base-model ~/Downloads/vosk-model-en-us-0.22-lgraph \\
                     --corpus ~/src \\
                     --output ~/models/vosk-custom

    # With compile package for full graph rebuild
    ./build_model.py --base-model ~/Downloads/vosk-model-en-us-0.22-lgraph \\
                     --corpus ~/src ~/docs \\
                     --compile-pkg ~/Downloads/vosk-model-en-us-0.22-compile \\
                     --output ~/models/vosk-custom
        """
    )

    parser.add_argument("--base-model", required=True,
                        help="Path to base Vosk model (lgraph format)")
    parser.add_argument("--corpus", nargs="+", required=True,
                        help="Paths to scan for vocabulary (git repos, directories)")
    parser.add_argument("--output", required=True,
                        help="Output directory for custom model")
    parser.add_argument("--compile-pkg",
                        help="Path to Vosk compile package (optional, for full rebuild)")

    args = parser.parse_args()

    builder = ModelBuilder(
        base_model=args.base_model,
        corpus_paths=args.corpus,
        output_dir=args.output,
        compile_pkg=args.compile_pkg,
    )

    builder.build()


if __name__ == "__main__":
    main()
