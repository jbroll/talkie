# Talkie Tools - Custom Vosk Model Builder

Tools for building custom Vosk speech recognition models with domain-specific vocabulary.

## How It Works

### The Problem

Vosk speech recognition models have a fixed vocabulary. Words not in the vocabulary
cannot be recognized - they'll be transcribed as similar-sounding known words.
For domain-specific terms (e.g., "critcl", "tcl", "vosk"), this is a problem.

### The Solution

We extract domain-specific vocabulary from your codebase and documentation,
generate pronunciations, and prepare files for rebuilding the Vosk language model.

### Architecture Overview

```
┌─────────────────────┐     ┌─────────────────────┐
│   Base Vosk Model   │     │   Your Codebase     │
│  (vosk-model-en-us- │     │  (markdown files,   │
│   0.22-lgraph)      │     │   README, docs)     │
└─────────┬───────────┘     └─────────┬───────────┘
          │                           │
          │ words.txt                 │ scan for words
          │ (368,707 words)           │ not in vocabulary
          ▼                           ▼
┌─────────────────────────────────────────────────┐
│              build_model.py                      │
│  1. Load base vocabulary from words.txt          │
│  2. Scan markdown files for unknown words        │
│  3. Extract context sentences containing words   │
│  4. Generate pronunciations via espeak-ng        │
└─────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────┐
│              Output Files                        │
│  • missing_words.txt - words to add              │
│  • contexts.txt - sentences for LM training      │
│  • extra.dic - pronunciations (word → phonemes)  │
└─────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────┐
│         Language Model Pipeline                  │
│  1. Build n-gram LM from contexts (make_kn_lm)   │
│  2. Interpolate with base LM (arpa_interpolate)  │
│  3. Prune low-value n-grams (arpa_prune)         │
│  4. Convert to FST format (arpa2fst)             │
└─────────────────────────────────────────────────┘
```

### Base Model

**vosk-model-en-us-0.22-lgraph** (~125MB)

Downloaded from: https://alphacephei.com/vosk/models

This is Vosk's English model in "lgraph" (lookahead graph) format:
- `graph/words.txt` - Vocabulary of 368,707 words with integer IDs
- `graph/HCLr.fst` - Hidden Markov Model + Context + Lexicon (static)
- `graph/Gr.fst` - Grammar/Language Model FST (replaceable)
- `am/` - Acoustic model (neural network weights)
- `conf/` - Configuration files

The lgraph format allows updating just the language model (Gr.fst) without
rebuilding the entire graph, making vocabulary additions faster.

### Missing Words Detection

**Source:** Markdown files (*.md) in the corpus directories

The `extract_vocabulary.py` script:
1. Finds all `.md` files in specified directories (respects .gitignore)
2. Extracts words using regex: `[a-zA-Z][a-zA-Z0-9_'-]*[a-zA-Z0-9]|[a-zA-Z]`
3. Normalizes to lowercase
4. Compares against `words.txt` from the base model
5. Counts occurrences (words appearing ≥2 times are kept)

Example missing words from the Talkie codebase:
- `critcl` (Tcl C extension tool)
- `vosk` (speech recognition library)
- `tcl` (programming language)
- `uinput` (Linux kernel input system)

### Context Sentences

**Source:** Same markdown files, sentences containing missing words

For each missing word, we extract the full sentence where it appears.
These sentences train the language model to understand word context.

Example context sentence:
> "Whenever a package declares libraries for preloading critcl will build
> a supporting shared library providing a Tcl package named preload"

Context helps the language model learn:
- What words typically appear before/after the new word
- The grammatical role of the word
- Domain-specific word combinations

### Pronunciation Generation

**Tool:** espeak-ng (text-to-speech with IPA output)

For each missing word, we generate a phonetic pronunciation:
```
critcl → k r I t k @ l
vosk → v A s k
tcl → t k @ l
```

The pronunciation uses Vosk's phoneme set (based on CMU dictionary format).
espeak-ng outputs IPA, which is then converted to Vosk phonemes.

## Installed/Downloaded Software

### System Packages (installed via package manager)

| Package | Purpose | Install Command (Void) |
|---------|---------|------------------------|
| espeak-ng | G2P pronunciation generation | `sudo xbps-install -y espeak-ng` |

### Python Packages (pip, in venv)

| Package | Purpose | Install |
|---------|---------|---------|
| kaldilm | ARPA to FST conversion (`arpa2fst`) | `pip install kaldilm` |

### Built from Source (in ~/src/fst-tools)

| Package | Version | Purpose |
|---------|---------|---------|
| OpenFST | 1.8.0 | FST CLI tools (fstcompile, fstarcsort, fstcompose, etc.) |

Built from [alphacep/openfst](https://github.com/alphacep/openfst) fork.
Installed to `~/src/fst-tools/install/`.

### Downloaded Files (in ~/Downloads)

| File | Size | Purpose |
|------|------|---------|
| `vosk-model-en-us-0.22-lgraph/` | ~125MB | Base model for recognition |
| `vosk-model-en-us-0.22-compile/` | ~3.2GB | Compile package (see breakdown below) |

**Compile package breakdown:**
- `db/en-230k-0.5.lm.gz` (1.9GB) - Base language model for interpolation
- `db/tedlium-release-3/` (526MB) - Test audio data
- `exp/` (638MB) - Trained acoustic model
- `db/en-g2p/` (105MB) - G2P model (Phonetisaurus)
- `utils/` (1.5MB) - Kaldi utility scripts (shell/perl/python)

### Graph Compilation Tools

To add new words to the Vosk model vocabulary, you need to rebuild the FST graph.
The lgraph model uses a split format (HCLr.fst + Gr.fst) that allows updating
just the language model graph.

**Current toolchain (all working):**
- `kaldilm.arpa2fst` (pip) - converts ARPA language model to FST format
- OpenFST CLI tools (built) - fstcompile, fstarcsort, fstcompose, fstinfo, etc.
- Python LM tools (this repo) - arpa_interpolate.py, arpa_prune.py

**Building OpenFST from source:**

The official openfst.org is behind Cloudflare and often inaccessible.
Use the alphacep fork instead:

```bash
mkdir -p ~/src/fst-tools && cd ~/src/fst-tools

# Clone alphacep's OpenFST fork (1.8.0)
git clone https://github.com/alphacep/openfst.git
cd openfst

# Build with ngram FST support
autoreconf -i
./configure --prefix=$HOME/src/fst-tools/install --enable-ngram-fsts
make -j4 && make install

# Add to environment (put in ~/.bashrc)
export PATH=$HOME/src/fst-tools/install/bin:$PATH
export LD_LIBRARY_PATH=$HOME/src/fst-tools/install/lib:$LD_LIBRARY_PATH
```

**Note:** OpenGrm-ngram is NOT needed. The Vosk compile scripts use SRILM's
`ngram` and `ngram-count` commands, which we replace with Python tools.

## Quick Start

```bash
# 1. Install espeak-ng for pronunciation generation
sudo xbps-install -y espeak-ng   # Void Linux

# 2. Build a custom model from your projects
cd /home/john/src/talkie
./tools/build_model.py \
    --base-model ~/Downloads/vosk-model-en-us-0.22-lgraph \
    --corpus ~/src \
    --output ~/models/vosk-custom

# Output structure:
#   ~/models/vosk-custom/
#   ├── model/              # Ready-to-use Vosk model (copy of base)
#   ├── build/
#   │   ├── dict/extra.dic  # New word pronunciations
#   │   └── corpus/         # Context sentences
#   └── manifest.json       # Build metadata
```

## Required Packages

### espeak-ng (Text-to-Speech / G2P)
Generates phonetic pronunciations from words using IPA, then converts to Vosk format.

```bash
# Void Linux
sudo xbps-install -y espeak-ng

# Ubuntu/Debian
sudo apt install espeak-ng

# Fedora
sudo dnf install espeak-ng

# Arch
sudo pacman -S espeak-ng
```

Verify installation:
```bash
espeak-ng --ipa -q "vosk"
# Should output: vˈɒsk
```

### Language Model Tools (Open Source Alternatives to SRILM)

The Vosk compile package uses SRILM, but we provide open source replacements:

| SRILM Command | Open Source Replacement |
|---------------|------------------------|
| `ngram-count` | Kaldi's `utils/lang/make_kn_lm.py` (Apache 2.0) |
| `ngram -mix-lm` | `tools/arpa_interpolate.py` (Apache 2.0) |
| `ngram -prune` | `tools/arpa_prune.py` (Apache 2.0) |

No external dependencies required - pure Python using only standard library.

## Vosk Compile Package

For adding custom vocabulary to Vosk models:

```bash
wget https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-compile.zip
unzip vosk-model-en-us-0.22-compile.zip
```

## Python Dependencies

The extraction script uses only standard library modules:
- `subprocess` - for git and espeak calls
- `pathlib` - for file handling
- `re` - for text processing
- `collections` - for defaultdict

No pip packages required.

## Tools

### build_model.py (Main Entry Point)

Orchestrates the complete model building pipeline.

```bash
./tools/build_model.py \
    --base-model ~/Downloads/vosk-model-en-us-0.22-lgraph \
    --corpus ~/src ~/docs \
    --output ~/models/vosk-custom \
    --compile-pkg ~/Downloads/vosk-model-en-us-0.22-compile  # Optional
```

**Steps performed:**
1. Copy base model to output directory
2. Scan corpus for missing vocabulary (respects .gitignore)
3. Generate pronunciations with espeak-ng
4. Prepare files for graph compilation

### extract_vocabulary.py (Standalone)

Can be used independently to scan for missing words.

```bash
# Basic usage
./tools/extract_vocabulary.py /path/to/search

# Limit pronunciation generation to top N words
TOP_WORDS=200 ./tools/extract_vocabulary.py /path/to/search
```

### arpa_interpolate.py (LM Mixing)

Interpolate two ARPA language models.

```bash
./tools/arpa_interpolate.py \
    --lm base.lm.gz \
    --mix-lm extra.lm \
    --lambda 0.95 \
    --output mixed.lm.gz
```

### arpa_prune.py (LM Pruning)

Reduce language model size by removing low-value n-grams.

```bash
./tools/arpa_prune.py \
    --lm mixed.lm.gz \
    --threshold 1e-8 \
    --output pruned.lm.gz
```

## Output Files

| File | Description |
|------|-------------|
| `build/corpus/missing_words.txt` | Words not in base vocabulary |
| `build/corpus/contexts.txt` | Context sentences for LM training |
| `build/dict/extra.dic` | Pronunciations in Vosk format |
| `manifest.json` | Build metadata |

## Integration with Vosk Compile Package

For full graph rebuild (requires Kaldi):

```bash
# Copy outputs to compile package
cp build/dict/extra.dic /path/to/vosk-compile/db/
cat build/corpus/contexts.txt >> /path/to/vosk-compile/db/extra.txt

# Run compilation
cd /path/to/vosk-compile
./compile-graph.sh
```

## Open Source Compilation Workflow

Complete workflow without SRILM (all Apache 2.0 licensed):

```bash
# 1. Extract vocabulary and pronunciations
./tools/extract_vocabulary.py ~/src
# Outputs: extra.dic, extra_contexts.txt

# 2. Build LM from custom text (using Kaldi's tool)
python3 utils/lang/make_kn_lm.py -ngram-order 4 \
    -text db/extra.txt \
    -lm data/extra.lm

# 3. Interpolate with base LM (using our tool)
./tools/arpa_interpolate.py \
    --lm db/en-230k-0.5.lm.gz \
    --mix-lm data/extra.lm \
    --lambda 0.95 \
    --output data/en-mix.lm.gz

# 4. Prune for smaller size (using our tool)
./tools/arpa_prune.py \
    --lm data/en-mix.lm.gz \
    --threshold 3e-8 \
    --output data/en-mix-small.lm.gz

# 5. Build graph (Kaldi - Apache 2.0)
utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang
utils/format_lm.sh data/lang data/en-mix-small.lm.gz data/dict/lexicon.txt data/lang_test
utils/mkgraph_lookahead.sh --self-loop-scale 1.0 data/lang exp/chain/tdnn data/en-mix-small.lm.gz exp/chain/tdnn/lgraph
```

## Tool Summary

| Tool | Purpose | License |
|------|---------|---------|
| `extract_vocabulary.py` | Find missing words, generate pronunciations | Apache 2.0 |
| `arpa_interpolate.py` | Mix language models | Apache 2.0 |
| `arpa_prune.py` | Reduce LM size | Apache 2.0 |
| espeak-ng | G2P pronunciation | GPL-3.0 |
| kaldilm | ARPA to FST conversion | Apache 2.0 |
| OpenFST | FST operations (CLI tools) | Apache 2.0 |
| Kaldi utils | Graph compilation scripts | Apache 2.0 |
