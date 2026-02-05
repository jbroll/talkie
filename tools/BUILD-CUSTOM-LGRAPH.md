# Building a Custom Vosk lgraph Model

This document describes how to rebuild the `vosk-model-en-us-0.22-lgraph` model with additional vocabulary words.

## Overview

The lgraph (lookahead graph) model separates the language model (Gr.fst) from the lexicon/acoustic model (HCLr.fst), making it easier to add vocabulary. This process:

1. Uses a **pruned vocabulary** (~232k words) matching the language model
2. Adds custom domain vocabulary from `compile/db/extra.txt`
3. Generates pronunciations for new words using Phonetisaurus G2P
4. Rebuilds the graph with proper `olabel_lookahead` FST format

## Model Structure

The model is self-contained with all rebuild artifacts in `compile/`:

```
vosk-model-en-us-0.22-lgraph/
├── am/                       # Acoustic model (do not modify)
│   ├── final.mdl
│   └── tree
├── conf/                     # Decoder configuration
├── graph/                    # Runtime graph (rebuild output)
│   ├── Gr.fst               # Language model FST
│   ├── HCLr.fst             # Lexicon/acoustic graph (olabel_lookahead)
│   ├── words.txt            # Vocabulary
│   └── phones/              # Phone definitions
├── ivector/                  # Speaker adaptation
└── compile/                  # Rebuild artifacts
    ├── compile-lgraph.sh    # Main build script
    ├── dict-pruned.py       # Lexicon generator (filters to LM words)
    ├── lgraph-base.lm.gz    # Base LM (extract once from Gr.fst)
    ├── missing_pronunciations.txt  # G2P for LM words not in en.dic
    ├── README.md            # Quick reference
    └── db/
        ├── en.dic           # Base pronunciation dictionary (~312k words)
        ├── en-g2p/en.fst    # Phonetisaurus G2P model
        ├── phone/           # Phone set definitions
        ├── extra.txt        # Domain vocabulary sentences (edit this)
        └── extra.dic        # Manual pronunciations (optional)
```

## Prerequisites

### Build Host Requirements

The build requires ~16GB RAM. Install these tools:

1. **Miniforge** (or Miniconda) with OpenGRM NGram:
   ```bash
   # Install miniforge (recommended over miniconda - no ToS issues)
   curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
   bash Miniforge3-$(uname)-$(uname -m).sh

   # Install ngram tools
   conda install -c conda-forge ngram
   pip install phonetisaurus
   ```

2. **Container Runtime** (Podman or Docker) with Kaldi:
   ```bash
   # Podman (preferred on Void Linux)
   podman pull docker.io/kaldiasr/kaldi:latest

   # Or Docker
   docker pull docker.io/kaldiasr/kaldi:latest
   ```

## One-Time Setup

These steps only need to be done once per model to prepare for rebuilding.

### 1. Extract base language model

The `lgraph-base.lm.gz` file must be extracted from the original `Gr.fst`:

```bash
cd /path/to/vosk-model-en-us-0.22-lgraph/compile

# Set up conda paths
export PATH=$HOME/miniforge3/bin:$PATH
export LD_LIBRARY_PATH=$HOME/miniforge3/lib:$LD_LIBRARY_PATH

# Extract ARPA from Gr.fst (takes ~1 minute)
ngramprint --ARPA ../graph/Gr.fst | gzip > lgraph-base.lm.gz
```

### 2. Generate missing pronunciations

Some words in the language model are not in en.dic. Generate pronunciations:

```bash
# Find words in LM but not in dictionary
python3 -c "
import gzip
lm_words = set()
with gzip.open('lgraph-base.lm.gz', 'rt') as f:
    in_unigrams = False
    for line in f:
        line = line.strip()
        if line == '\\\\1-grams:':
            in_unigrams = True
        elif line.startswith('\\\\') and in_unigrams:
            break
        elif in_unigrams and line:
            parts = line.split('\t')
            if len(parts) >= 2 and not parts[1].startswith('<'):
                lm_words.add(parts[1])

dic_words = set(line.split()[0].split('(')[0] for line in open('db/en.dic'))
missing = lm_words - dic_words
print('\n'.join(sorted(missing)))
" > missing_words.txt

# Generate pronunciations with Phonetisaurus
python3 -c "
import phonetisaurus
words = set(open('missing_words.txt').read().split())
with open('missing_pronunciations.txt', 'w') as out:
    for word, phones in phonetisaurus.predict(words, 'db/en-g2p/en.fst'):
        out.write(f'{word} {\" \".join(phones)}\n')
"

rm missing_words.txt
```

## Adding Domain Vocabulary

### Option A: Extract from corpus (recommended)

Use the `extract_vocabulary.py` tool to find missing words in your markdown files:

```bash
cd /path/to/talkie

# Extract vocabulary from your source directories
./tools/extract_vocabulary.py ~/src ~/Documents/notes \
    --model ~/Downloads/vosk-model-en-us-0.22-lgraph \
    --output ~/Downloads/vosk-model-en-us-0.22-lgraph/compile/db \
    --top 500 \
    --min-occurrences 3

# This creates:
#   db/extra.txt  - Context sentences containing missing words
#   db/extra.dic  - G2P pronunciations for missing words
```

### Option B: Manual vocabulary

Add domain-specific words directly:

```bash
cd /path/to/vosk-model-en-us-0.22-lgraph/compile

# Add sentences containing your words (for LM context)
cat >> db/extra.txt << 'EOF'
kubernetes kubectl pods deployments
nginx reverse proxy configuration
EOF

# Add manual pronunciations for tricky words
cat >> db/extra.dic << 'EOF'
kubectl K UW B K T L
nginx E N JH IH N EH K S
EOF
```

### Rebuild the graph

```bash
cd /path/to/vosk-model-en-us-0.22-lgraph/compile
./compile-lgraph.sh
```

The script:
1. Generates pruned lexicon (LM words + domain words from extra.txt)
2. Runs Kaldi's `prepare_lang.sh` to create language files
3. Builds `Gr.fst` from the base language model
4. Builds `HCLr.fst` with olabel_lookahead format
5. Installs to `../graph/` (backs up previous to `../graph.bak/`)

## Remote Build Workflow

If building on a remote host (e.g., GPU server with more RAM):

```bash
# Copy model to remote
scp -r ~/Downloads/vosk-model-en-us-0.22-lgraph user@remote:~/

# Run one-time setup on remote (if not done)
ssh user@remote "cd ~/vosk-model-en-us-0.22-lgraph/compile && \
    export PATH=\$HOME/miniforge3/bin:\$PATH && \
    ngramprint --ARPA ../graph/Gr.fst | gzip > lgraph-base.lm.gz"

# Copy vocabulary files to remote
scp ~/Downloads/vosk-model-en-us-0.22-lgraph/compile/db/extra.* \
    user@remote:~/vosk-model-en-us-0.22-lgraph/compile/db/

# Build on remote
ssh user@remote "cd ~/vosk-model-en-us-0.22-lgraph/compile && \
    CONTAINER_CMD=docker ./compile-lgraph.sh"

# Copy result back
scp -r user@remote:~/vosk-model-en-us-0.22-lgraph/graph \
    ~/Downloads/vosk-model-en-us-0.22-lgraph/
```

## Output Files

After successful build:

| File | Size | Description |
|------|------|-------------|
| graph/HCLr.fst | ~27MB | Lexicon/acoustic graph (olabel_lookahead) |
| graph/Gr.fst | ~77MB | Language model (const format) |
| graph/words.txt | ~3.6MB | Vocabulary (~239k words) |

## Troubleshooting

### "lgraph-base.lm.gz not found"

Run the one-time extraction step above.

### Model produces garbage output

Check HCLr.fst has correct type:
```bash
file ~/Downloads/vosk-model-en-us-0.22-lgraph/graph/HCLr.fst
# Should show: fst type: olabel_lookahead
```

If it shows `fst type: vector`, the lookahead conversion failed.

### Missing words

Check vocabulary includes your word:
```bash
grep "yourword" ~/Downloads/vosk-model-en-us-0.22-lgraph/graph/words.txt
```

If missing, ensure it's in `db/extra.txt` and rebuild.

### Restore previous graph

```bash
cd ~/Downloads/vosk-model-en-us-0.22-lgraph
rm -rf graph && mv graph.bak graph
```

### Container permission errors

If files are created as root by container:
```bash
sudo chown -R $USER:$USER compile/data compile/build
```

## References

- [Vosk LM Documentation](https://alphacephei.com/vosk/lm)
- [Vosk Model Adaptation](https://alphacephei.com/vosk/adaptation)
- [Kaldi mkgraph_lookahead.sh](https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/utils/mkgraph_lookahead.sh)
