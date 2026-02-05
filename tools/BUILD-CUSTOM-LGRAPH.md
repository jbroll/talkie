# Building a Custom Vosk lgraph Model

This document describes how to rebuild the `vosk-model-en-us-0.22-lgraph` model with additional vocabulary words.

## Overview

The lgraph (lookahead graph) model separates the language model (Gr.fst) from the lexicon/acoustic model (HCLr.fst), making it easier to add vocabulary. This process:

1. Uses a **pruned vocabulary** (~232k words) matching the language model
2. Adds custom domain vocabulary from `compile/db/extra.txt`
3. Generates pronunciations for new words using Phonetisaurus G2P
4. Rebuilds the graph with proper `olabel_lookahead` FST format

## Vocabulary Pruning

The pronunciation dictionary (en.dic) contains ~312k words including many archaic
spellings and variants that are not in the language model. Since words without LM
probability can never be selected by the decoder, we prune the vocabulary to only
include words that appear in the language model:

- **en.dic**: 312k words (includes archaic/unused words)
- **Language model**: 231k words (from training corpus)
- **Pruned vocabulary**: ~232k words (LM words + domain words)

This reduces the vocabulary by ~37% and eliminates words that could never be output.

## Model Structure

The model is self-contained with all rebuild artifacts in `compile/`:

```
vosk-model-en-us-0.22-lgraph/
├── README
├── am/
│   ├── final.mdl              # Acoustic model
│   └── tree                   # Decision tree
├── conf/                      # Decoder configuration
├── graph/                     # Runtime graph (rebuild output)
│   ├── Gr.fst                 # Language model FST
│   ├── HCLr.fst               # Lexicon/acoustic graph
│   ├── words.txt              # Vocabulary
│   ├── phones.txt             # Phone symbols
│   └── phones/                # Phone definitions
├── ivector/                   # Speaker adaptation
└── compile/                   # Rebuild artifacts (~115MB)
    ├── README.md              # Quick reference
    ├── compile-lgraph.sh      # Main build script
    ├── dict-pruned.py         # Lexicon generator
    ├── lgraph-base.lm.gz      # Base LM (extract once from Gr.fst)
    ├── missing_pronunciations.txt  # G2P for LM words not in en.dic
    └── db/
        ├── en.dic             # Base pronunciation dictionary
        ├── en-g2p/en.fst      # Phonetisaurus G2P model
        ├── phone/             # Phone set definitions
        ├── extra.txt          # Domain vocabulary (edit this)
        └── extra.dic          # Manual pronunciations (optional)
```

## Prerequisites

### Build Host (GPU or high-memory machine)

The build requires ~16GB RAM and is typically done on a remote host with:

- **Conda/Miniconda** with OpenGRM and Phonetisaurus:
  ```bash
  conda install -c conda-forge openfst opengrm-ngram
  pip install phonetisaurus
  ```

- **Podman** with Kaldi container:
  ```bash
  podman pull docker.io/kaldiasr/kaldi:latest
  ```

## One-Time Setup

These steps only need to be done once to prepare the model for rebuilding.

### 1. Copy model to build host

```bash
scp -r ~/Downloads/vosk-model-en-us-0.22-lgraph john@gpu:~/
```

### 2. Extract base language model

The `lgraph-base.lm.gz` file must be extracted from the original `Gr.fst`:

```bash
ssh john@gpu
cd ~/vosk-model-en-us-0.22-lgraph/compile

export PATH=$HOME/miniconda3/bin:$PATH
export LD_LIBRARY_PATH=$HOME/miniconda3/lib:$HOME/miniconda3/lib/fst:$LD_LIBRARY_PATH

ngramprint --ARPA ../graph/Gr.fst | gzip > lgraph-base.lm.gz
```

### 3. Generate missing pronunciations

Some words in the LM are not in en.dic. Generate pronunciations for them:

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
            parts = line.split('\\t')
            if len(parts) >= 2 and not parts[1].startswith('<'):
                lm_words.add(parts[1])

dic_words = set(line.split()[0].split('(')[0] for line in open('db/en.dic'))
missing = lm_words - dic_words
print('\\n'.join(sorted(missing)))
" > missing_words.txt

# Generate pronunciations
python3 -c "
import phonetisaurus
words = set(open('missing_words.txt').read().split())
with open('missing_pronunciations.txt', 'w') as out:
    for word, phones in phonetisaurus.predict(words, 'db/en-g2p/en.fst'):
        out.write(f'{word} {\" \".join(phones)}\n')
"

rm missing_words.txt
```

### 4. Copy updated model back to local (optional)

If you want the local copy to have the generated files:

```bash
scp john@gpu:~/vosk-model-en-us-0.22-lgraph/compile/lgraph-base.lm.gz \
    john@gpu:~/vosk-model-en-us-0.22-lgraph/compile/missing_pronunciations.txt \
    ~/Downloads/vosk-model-en-us-0.22-lgraph/compile/
```

## Adding Domain Vocabulary

### 1. Edit db/extra.txt

Add domain-specific text containing words you want recognized:

```bash
ssh john@gpu "cat >> ~/vosk-model-en-us-0.22-lgraph/compile/db/extra.txt << 'EOF'
your domain specific words and phrases here
technical terms product names etc
EOF"
```

Or edit locally and copy:

```bash
echo "myterm anotherterm" >> ~/Downloads/vosk-model-en-us-0.22-lgraph/compile/db/extra.txt
scp ~/Downloads/vosk-model-en-us-0.22-lgraph/compile/db/extra.txt \
    john@gpu:~/vosk-model-en-us-0.22-lgraph/compile/db/
```

### 2. (Optional) Add manual pronunciations

For words where G2P might produce incorrect results, add to `db/extra.dic`:

```bash
ssh john@gpu "cat >> ~/vosk-model-en-us-0.22-lgraph/compile/db/extra.dic << 'EOF'
kubectl k UW b k T L
nginx E N JH IH N EH K S
EOF"
```

### 3. Rebuild the graph

```bash
ssh john@gpu "cd ~/vosk-model-en-us-0.22-lgraph/compile && ./compile-lgraph.sh"
```

The script:
1. Generates the pruned lexicon (filters en.dic to LM words + domain words)
2. Runs Kaldi's `prepare_lang.sh` to create language files
3. Builds `Gr.fst` from the base LM
4. Builds `HCLr.fst` with olabel_lookahead format
5. Installs the new graph to `../graph/` (backs up previous to `../graph.bak/`)

### 4. Copy updated model to local machine

```bash
scp -r john@gpu:~/vosk-model-en-us-0.22-lgraph/graph \
    ~/Downloads/vosk-model-en-us-0.22-lgraph/
```

Or sync the entire model:

```bash
rsync -av john@gpu:~/vosk-model-en-us-0.22-lgraph/ \
    ~/Downloads/vosk-model-en-us-0.22-lgraph/
```

## Output Files

The build produces in `graph/`:

| File | Size | Description |
|------|------|-------------|
| HCLr.fst | ~27MB | Lexicon/acoustic graph (olabel_lookahead format) |
| Gr.fst | ~80MB | Language model (const format) |
| words.txt | ~3.5MB | Vocabulary (~232k words, pruned to LM) |
| phones.txt | ~2KB | Phone symbols |
| phones/ | - | Phone definitions |

## Troubleshooting

### "lgraph-base.lm.gz not found"

Run the one-time extraction step (section above).

### Model produces garbage output

Check that HCLr.fst has the correct FST type:

```bash
file ~/Downloads/vosk-model-en-us-0.22-lgraph/graph/HCLr.fst
# Should show: fst type: olabel_lookahead
```

If it shows `fst type: vector`, the lookahead conversion failed. Check that the Kaldi container has the lookahead library:

```bash
podman run --rm docker.io/kaldiasr/kaldi:latest \
    ls /opt/kaldi/tools/openfst-1.8.4/lib/fst/olabel_lookahead-fst.so
```

### Missing words

Check the vocabulary includes your word:

```bash
grep "yourword" ~/Downloads/vosk-model-en-us-0.22-lgraph/graph/words.txt
```

If missing, ensure it's in `db/extra.txt` and rebuild.

### Restore previous graph

If the new graph has issues:

```bash
ssh john@gpu "cd ~/vosk-model-en-us-0.22-lgraph && rm -rf graph && mv graph.bak graph"
```

## References

- [Vosk LM Documentation](https://alphacephei.com/vosk/lm)
- [Vosk Model Adaptation](https://alphacephei.com/vosk/adaptation)
- [Kaldi mkgraph_lookahead.sh](https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/utils/mkgraph_lookahead.sh)
