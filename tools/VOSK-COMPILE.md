# Vosk Model Compilation

Documentation for the Vosk language model compilation setup.

## Local Copy

Key scripts and phone definitions are copied to `tools/vosk-compile/`:

```
tools/vosk-compile/
├── compile-graph.sh      # Main compilation script
├── remote-compile.sh     # Podman-based compilation
├── dict.py               # Dictionary builder with G2P
├── path.sh               # Kaldi environment setup
├── path.local.sh         # Local path overrides
├── extra.txt             # Custom text for LM interpolation
├── extra.dic             # Custom pronunciations
├── phone/                # Phone set definitions
│   ├── nonsilence_phones.txt
│   ├── silence_phones.txt
│   ├── optional_silence.txt
│   └── extra_questions.txt
├── README
└── RESULTS.txt
```

## GPU Host Location

Large data files remain on the GPU host:

```
gpu:~/vosk-compile/
```

## Directory Structure

```
vosk-compile/
├── db/                          # Source data
│   ├── en-230k-0.5.lm.gz       # Base ARPA language model (1.9GB)
│   ├── en.dic                   # Main pronunciation dictionary
│   ├── extra.txt                # Custom text for LM interpolation
│   ├── extra.dic                # Custom pronunciations
│   ├── phone/                   # Phone set definitions
│   └── en-g2p/                  # Grapheme-to-phoneme model
├── data/                        # Working data (generated)
│   ├── dict/                    # Combined dictionary
│   ├── lang/                    # Language files
│   ├── lang_test/               # Test language files
│   └── *.lm.gz                  # Intermediate LM files
├── exp/
│   ├── chain/tdnn/              # Acoustic model
│   │   └── graph/               # Compiled recognition graph
│   └── rnnlm/                   # RNNLM rescoring model
├── compile-graph.sh             # Main compilation script (native)
├── remote-compile.sh            # Podman-based compilation
├── dict.py                      # Dictionary builder with G2P
└── path.sh                      # Kaldi environment setup
```

## Key Files

### compile-graph.sh

Main compilation script (runs natively with Kaldi installed):

```bash
#!/bin/bash
. path.sh
set -x

rm -rf data/*.lm.gz data/lang_local data/dict data/lang data/lang_test data/lang_test_rescore
rm -rf exp/lgraph exp/graph

mkdir -p data/dict
cp db/phone/* data/dict
python3 ./dict.py > data/dict/lexicon.txt

# Build custom LM from extra.txt, interpolate with base LM
ngram-count -wbdiscount -order 4 -text db/extra.txt -lm data/extra.lm.gz
ngram -order 4 -lm db/en-230k-0.5.lm.gz -mix-lm data/extra.lm.gz -lambda 0.95 -write-lm data/en-mix.lm.gz
ngram -order 4 -lm data/en-mix.lm.gz -prune 3e-8 -write-lm data/en-mixp.lm.gz
ngram -lm data/en-mixp.lm.gz -write-lm data/en-mix-small.lm.gz

utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang
utils/format_lm.sh data/lang data/en-mix-small.lm.gz data/dict/lexicon.txt data/lang_test
utils/mkgraph.sh --self-loop-scale 1.0 data/lang_test exp/chain/tdnn exp/chain/tdnn/graph
utils/build_const_arpa_lm.sh data/en-mix.lm.gz data/lang_test data/lang_test_rescore

rnnlm/change_vocab.sh data/lang/words.txt exp/rnnlm exp/rnnlm_out
utils/mkgraph_lookahead.sh --self-loop-scale 1.0 data/lang exp/chain/tdnn data/en-mix-small.lm.gz exp/chain/tdnn/lgraph
```

### remote-compile.sh

Containerized compilation using Podman (no local Kaldi needed):

```bash
#!/bin/bash
set -ex
cd ~/vosk-compile

podman run --rm -v ~/vosk-compile:/work -v ~/vosk-tools:/tools -w /work docker.io/kaldiasr/kaldi:latest bash -c '
set -ex
export PATH=/tools:/opt/kaldi/src/fstbin:/opt/kaldi/src/bin:/opt/kaldi/src/lmbin:/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/egs/wsj/s5/utils:$PATH
export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/src/lib:$LD_LIBRARY_PATH

ngram-count -wbdiscount -order 4 -text db/extra.txt -lm data/extra.lm.gz
ngram -order 4 -lm db/en-230k-0.5.lm.gz -mix-lm data/extra.lm.gz -lambda 0.95 -write-lm data/en-mix.lm.gz
ngram -order 4 -lm data/en-mix.lm.gz -prune 3e-8 -write-lm data/en-mix-small.lm.gz

rm -rf data/lang_local data/lang
utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang

rm -rf data/lang_test
utils/format_lm.sh data/lang data/en-mix-small.lm.gz data/dict/lexicon.txt data/lang_test

if [ -d exp/chain/tdnn ]; then
    rm -rf exp/chain/tdnn/graph
    utils/mkgraph.sh --self-loop-scale 1.0 data/lang_test exp/chain/tdnn exp/chain/tdnn/graph
fi
'
```

### dict.py

Builds lexicon from dictionaries with G2P fallback for unknown words:

```python
#!/usr/bin/python3
import phonetisaurus

words = {}

for line in open("db/en.dic"):
    items = line.split()
    if items[0] not in words:
         words[items[0]] = []
    words[items[0]].append(" ".join(items[1:]))

for line in open("db/extra.dic"):
    items = line.split()
    if items[0] not in words:
         words[items[0]] = []
    words[items[0]].append(" ".join(items[1:]))

new_words = set()
for line in open("db/extra.txt"):
    for w in line.split():
        if w not in words:
             new_words.add(w)

for w, phones in phonetisaurus.predict(new_words, "db/en-g2p/en.fst"):
    words[w] = []
    words[w].append(" ".join(phones))

for w, phones in words.items():
    for p in phones:
        print (w, p)
```

## Phone Set

The model uses ARPAbet-style phones:

**Vowels**: `@ @\` 3\` A E E: I O OI U V aI aU eI i oU u {`

**Consonants**: `b d dZ f g h j k l m n p r s t tS v w z D N S T Z`

**Silence/Noise**: `SIL LAUGHTER NOISE OOV SPN BRH CGH NSN SMK UHH UM`

## Customization Workflow

1. Add custom text to `db/extra.txt`
2. Add custom pronunciations to `db/extra.dic` (optional - G2P handles unknowns)
3. Run `./remote-compile.sh` or `./compile-graph.sh`
4. Copy `exp/chain/tdnn/graph/` to model directory

## Extracting Data for POS Service

The ARPA language model contains n-gram probabilities used by the POS service:

```bash
# Extract word bigrams
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 tools/extract-word-bigrams.py > tools/word-bigrams.tsv

# Extract distinguishing trigrams
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 tools/extract-distinguishing-trigrams.py tools/word-bigrams.tsv > tools/distinguishing-trigrams.tsv
```

## Model Performance

From RESULTS.txt (TED-LIUM test set):

| Decode Method | WER |
|---------------|-----|
| Base | 8.11% |
| Lookahead | 8.10% |
| Rescore | 6.57% |
| RNNLM | 5.91% |

## Dependencies

- Kaldi (or kaldiasr/kaldi Docker image)
- SRILM (ngram tools) - wrapper scripts in `~/vosk-tools/`
- OpenFST
- Phonetisaurus (for G2P)

## Source Data (GPU Host Only)

These large files remain on the GPU host and are accessed via ssh:

| File | Size | Description |
|------|------|-------------|
| `db/en-230k-0.5.lm.gz` | 1.9 GB | Base ARPA language model |
| `db/en.dic` | ~10 MB | 428k pronunciations |
| `db/en-g2p/en.fst` | - | Grapheme-to-phoneme model |
| `exp/chain/tdnn/` | - | Acoustic model |
| `exp/rnnlm/` | ~230 MB | RNNLM rescoring model |
