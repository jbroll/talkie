# Building Custom Vosk Models

This document describes the procedure for building custom Vosk speech recognition
models with domain-specific vocabulary.

## Overview

```
┌─────────────────────┐     ┌─────────────────────┐
│   Base Model        │     │   Your Codebase     │
│   vosk-model-en-us- │     │   (*.md, *.txt)     │
│   0.22-lgraph       │     │                     │
└─────────┬───────────┘     └─────────┬───────────┘
          │                           │
          │ 368k words                │ scan for missing words
          ▼                           ▼
┌───────────────────────────────────────────────────┐
│         Local: extract_vocabulary.py              │
│   1. Find words not in base vocabulary            │
│   2. Extract context sentences                    │
│   3. Generate pronunciations (Phonetisaurus)      │
└───────────────────────────────────────────────────┘
          │
          │ extra.dic, extra_contexts.txt
          ▼
┌───────────────────────────────────────────────────┐
│         GPU Host: compile-lgraph-v9.sh            │
│   1. Merge dictionaries (en.dic + extra.dic)      │
│   2. Build domain LM from context sentences       │
│   3. Interpolate with base LM (30% domain)        │
│   4. Build FST graph (Kaldi via Podman)           │
│   5. Assemble output model with all config files  │
└───────────────────────────────────────────────────┘
          │
          ▼
┌───────────────────────────────────────────────────┐
│            Custom Model                            │
│   ~/models/vosk-custom-lgraph/                     │
│   ├── am/final.mdl, tree                          │
│   ├── conf/mfcc.conf, model.conf, online_cmvn.conf│
│   ├── ivector/final.ie, splice.conf, ...          │
│   └── graph/HCLr.fst, Gr.fst, words.txt,          │
│          disambig_tid.int, phones/                │
└───────────────────────────────────────────────────┘
```

## Architecture

The build process is split between local machine and GPU host:

- **Local machine**: Vocabulary extraction (low memory)
- **GPU host**: LM interpolation and FST graph building (~16GB+ RAM)

### Required Files in Output Model

| Directory | File | Purpose |
|-----------|------|---------|
| am/ | final.mdl | Acoustic model |
| am/ | tree | Decision tree |
| conf/ | mfcc.conf | MFCC feature extraction (high-freq=7600) |
| conf/ | model.conf | Decoder parameters (beam, lattice-beam) |
| conf/ | online_cmvn.conf | Cepstral mean normalization |
| ivector/ | final.dubm | Diagonal UBM |
| ivector/ | final.ie | iVector extractor |
| ivector/ | final.mat | LDA matrix |
| ivector/ | global_cmvn.stats | Global CMVN stats |
| ivector/ | online_cmvn.conf | Online CMVN config |
| ivector/ | splice.conf | Splice context (--left-context=3, --right-context=3) |
| graph/ | HCLr.fst | Lexicon FST (olabel_lookahead type) |
| graph/ | Gr.fst | Language model FST (const type) |
| graph/ | words.txt | Word to ID mapping |
| graph/ | phones.txt | Phone to ID mapping |
| graph/ | disambig_tid.int | Disambiguation symbols |
| graph/ | phones/ | Phone set files |

## Prerequisites

### Local Machine

1. **Phonetisaurus** (for G2P pronunciation generation):
```bash
pip install --break-system-packages phonetisaurus
```

2. **Base Vosk model** (for vocabulary reference):
```bash
cd ~/Downloads
wget https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-lgraph.zip
unzip vosk-model-en-us-0.22-lgraph.zip
```

### GPU Host

1. **Podman** with Kaldi container:
```bash
podman pull docker.io/kaldiasr/kaldi:latest
```

2. **Vosk compile package**:
```bash
cd ~/Downloads
wget https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-compile.zip
unzip vosk-model-en-us-0.22-compile.zip
```

3. **OpenGRM ngram tools** (via miniconda):
```bash
conda install -c conda-forge opengrm-ngram
```

4. **Build environment** at `~/vosk-lgraph-compile/`:
   - `compile-lgraph-v9.sh` - Main build script
   - `dict-full.py` - Dictionary merger
   - `arpa_interpolate.py` - LM interpolation
   - `arpa_prune.py` - LM pruning
   - `db/` - Base dictionaries and LM
   - `exp/chain/` - Acoustic model and extractor

## Tool Summary

| Tool | Location | Purpose |
|------|----------|---------|
| `extract_vocabulary.py` | Local (tools/) | Find missing words, generate extra.dic |
| `phonetic_similarity.py` | Local (tools/) | Find acoustically similar words for confusion analysis |
| `deploy_and_build.sh` | Local (tools/) | Orchestrate local+remote build |
| `compile-lgraph-v9.sh` | GPU host | Full model build |
| `dict-full.py` | GPU host | Merge en.dic + base_missing.dic + extra.dic |
| `arpa_interpolate.py` | GPU host | Interpolate base + domain LM |
| `arpa_prune.py` | GPU host | Prune low-probability n-grams |

## Usage

### Quick Build

```bash
cd ~/src/talkie/tools

# Extract vocabulary locally, build on GPU host, fetch result
./deploy_and_build.sh ~/src/talkie
```

### Manual Build

#### Step 1: Extract Vocabulary (Local)

```bash
cd ~/src/talkie/tools

./extract_vocabulary.py \
    --output /tmp/vocab-deploy \
    --min-occurrences 5 \
    --max-length 20 \
    --max-hyphens 1 \
    ~/src/talkie

# Creates:
#   /tmp/vocab-deploy/missing_words.txt  - Words not in base vocabulary
#   /tmp/vocab-deploy/extra_contexts.txt - Context sentences for LM
#   /tmp/vocab-deploy/extra.dic          - Pronunciations for new words
```

#### Step 2: Deploy to GPU Host

```bash
scp /tmp/vocab-deploy/extra.dic john@gpu:~/vosk-lgraph-compile/db/
scp /tmp/vocab-deploy/extra_contexts.txt john@gpu:~/vosk-lgraph-compile/db/extra.txt
```

#### Step 3: Build on GPU Host

```bash
ssh john@gpu "cd ~/vosk-lgraph-compile && ./compile-lgraph-v9.sh"
```

#### Step 4: Fetch Result

```bash
scp -r john@gpu:~/models/vosk-custom-lgraph ~/src/talkie/models/vosk/custom/
```

## Configuration Details

### mfcc.conf (Critical Settings)

```
--sample-frequency=16000
--use-energy=false
--num-mel-bins=40
--num-ceps=40
--low-freq=20
--high-freq=7600          # MUST be 7600, not -400
--allow-upsample=true
--allow-downsample=true
```

### model.conf (Decoder Settings)

```
--min-active=200
--max-active=7000
--beam=13.0               # Increase to 18-20 for more alternatives
--lattice-beam=6.0        # Increase to 8-10 for more diverse hypotheses
--acoustic-scale=1.0
--frame-subsampling-factor=3
--endpoint.silence-phones=1:2:3:4:5:11:12:13:14:15
--endpoint.rule2.min-trailing-silence=0.5
--endpoint.rule3.min-trailing-silence=1.0
--endpoint.rule4.min-trailing-silence=2.0
```

### LM Interpolation Weight

The domain LM is interpolated with lambda=0.70 (30% domain, 70% base).
Adjust in `compile-lgraph-v9.sh` if needed:
- Higher domain weight: Better domain word recognition, worse general English
- Lower domain weight: Better general English, domain words may not be recognized

## Vocabulary Gap

The lgraph model has 368,702 words but en.dic only has 312,331 pronunciations.
The 56,371 word gap is filled by `base_missing.dic` (pre-generated with Phonetisaurus).

Dictionary merge order:
1. `en.dic` (312k words - CMU dictionary)
2. `base_missing.dic` (56k words - generated)
3. `extra.dic` (domain words - from your corpus)

## Troubleshooting

### Model fails to load

Check for missing files:
```bash
ls -la ~/models/vosk-custom-lgraph/{conf,ivector,graph}/
# Must have: mfcc.conf, model.conf, splice.conf, disambig_tid.int
```

Check mfcc.conf:
```bash
grep high-freq ~/models/vosk-custom-lgraph/conf/mfcc.conf
# Must be: --high-freq=7600 (NOT -400)
```

### HCLr.fst wrong type

```bash
head -c 50 ~/models/vosk-custom-lgraph/graph/HCLr.fst | strings
# Must contain: olabel_lookahead
```

### Word not recognized

1. Check word is in vocabulary:
```bash
grep -i "yourword" ~/models/vosk-custom-lgraph/graph/words.txt
```

2. Check pronunciation exists:
```bash
grep -i "yourword" ~/vosk-lgraph-compile/db/extra.dic
```

3. Check if word appears in alternatives (enable -alternatives 3 in Talkie)

### Domain words sound like common words

Use `phonetic_similarity.py` to identify potential confusions:
```bash
./phonetic_similarity.py --common-only critcl kupries vosk
```

Output shows phonetically similar common words (* marks likely confusions):
```
'critcl' /k r I t k @ l/
  1.0  critical             /k r I 4 I k @ l/ *

'kupries' /k V p r i z/
  0.0  capri's              /k V p r i z/
  1.0  caprice              /k @ p r i s/
```

The weighted phoneme distance accounts for:
- Similar sounds (t/d/4 tap, s/z, reduced vowels) cost 0.5
- Inserting/deleting reduced vowels (@, I, V) costs 0.5
- Other substitutions/insertions cost 1.0

Words with distance < 1.5 to common English words will likely be misrecognized.
The LM boost may not be enough to overcome acoustic similarity.
Consider post-processing with context-aware substitution.

## Known Limitations

1. **Acoustic similarity**: Words that sound like common English words may not be
   recognized even with high domain LM weight. The acoustic model was trained on
   common speech and strongly prefers frequent word patterns.

2. **Memory requirements**: LM interpolation requires ~16GB+ RAM. Use GPU host
   for building.

3. **Build time**: Full rebuild takes 5-10 minutes depending on vocabulary size.

## References

- [Vosk Model Adaptation](https://alphacephei.com/vosk/adaptation)
- [Kaldi Documentation](https://kaldi-asr.org/doc/)
- [OpenGRM NGram](https://www.opengrm.org/twiki/bin/view/GRM/NGramLibrary)
