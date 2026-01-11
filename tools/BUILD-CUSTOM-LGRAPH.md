# Building a Custom Vosk lgraph Model

This document describes how to build a custom `vosk-model-en-us-0.22-lgraph` model with additional vocabulary words.

## Overview

The lgraph (lookahead graph) model separates the language model (Gr.fst) from the lexicon/acoustic model (HCLr.fst), making it easier to add vocabulary. This process:

1. Uses a **pruned vocabulary** (~232k words) matching the language model
2. Adds custom domain vocabulary from `db/extra.txt`
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

## Prerequisites

### Remote GPU Host (john@gpu)

The build requires significant memory and is done on a remote host with:

- **Conda/Miniconda** with OpenGRM and Phonetisaurus:
  ```bash
  conda install -c conda-forge openfst opengrm-ngram
  $HOME/miniconda3/bin/pip install phonetisaurus
  ```

- **Podman** with Kaldi container:
  ```bash
  podman pull docker.io/kaldiasr/kaldi:latest
  ```

### Local Machine

- Vosk compile package: `~/Downloads/vosk-model-en-us-0.22-compile/`
- Original lgraph model: `~/Downloads/vosk-model-en-us-0.22-lgraph/`

## Directory Structure on GPU Host

```
~/vosk-lgraph-compile/
├── compile-lgraph.sh         # Main build script
├── dict-pruned.py            # Lexicon generator (filters to LM words only)
├── lgraph-base.arpa          # Extracted base LM (89MB)
├── data/
│   ├── lgraph-base.lm.gz     # Gzipped base LM
│   └── ...                   # Build artifacts
├── db/
│   ├── en.dic                # Base pronunciation dictionary (312k words)
│   ├── en-g2p/en.fst         # G2P model for new words
│   ├── extra.txt             # Domain text (add your words here)
│   ├── extra.dic             # Manual pronunciations (optional)
│   └── phone/                # Phone set definitions
├── exp/chain/tdnn/
│   ├── final.mdl             # Acoustic model
│   ├── tree                  # Decision tree
│   └── lgraph/               # Output directory
└── missing_pronunciations.txt # Generated pronunciations for 56k words
```

## Initial Setup (One-Time)

### 1. Copy compile package to GPU host

```bash
scp -r ~/Downloads/vosk-model-en-us-0.22-compile john@gpu:~/vosk-lgraph-compile
```

### 2. Extract base LM from original lgraph

The original lgraph's Gr.fst contains a heavily pruned LM. Extract it:

```bash
ssh john@gpu
cd ~/vosk-lgraph-compile
export PATH=$HOME/miniconda3/bin:$PATH
export LD_LIBRARY_PATH=$HOME/miniconda3/lib:$HOME/miniconda3/lib/fst:$LD_LIBRARY_PATH

# Copy original Gr.fst (need to get from local machine first)
# Then extract ARPA:
ngramprint --ARPA path/to/original/Gr.fst > lgraph-base.arpa
gzip -c lgraph-base.arpa > data/lgraph-base.lm.gz
```

### 3. Generate pronunciations for missing vocabulary

The original lgraph has 368k words but the compile package only has 312k. Generate pronunciations for the 56k missing words:

```bash
# Extract words from original lgraph (on local machine)
awk '{print $1}' ~/Downloads/vosk-model-en-us-0.22-lgraph/graph/words.txt | \
    grep -vE "^(<|#)" | sort -u > /tmp/lgraph_words.txt

# Extract words from compile package
awk '{print $1}' ~/Downloads/vosk-model-en-us-0.22-compile/db/en.dic | \
    sort -u > /tmp/compile_words.txt

# Find missing words
comm -23 /tmp/lgraph_words.txt /tmp/compile_words.txt > /tmp/missing_words.txt

# Copy to GPU and generate pronunciations
scp /tmp/missing_words.txt john@gpu:~/vosk-lgraph-compile/missing_real_words.txt

ssh john@gpu "cd ~/vosk-lgraph-compile && \$HOME/miniconda3/bin/python3 -c \"
import phonetisaurus
words = set(open('missing_real_words.txt').read().split())
with open('missing_pronunciations.txt', 'w') as out:
    for word, phones in phonetisaurus.predict(words, 'db/en-g2p/en.fst'):
        out.write(f'{word} {\\\" \\\".join(phones)}\\n')
\""
```

### 4. Create dict-pruned.py

This script builds the lexicon by filtering en.dic to only include words that
appear in the language model. Words not in the LM would never be output anyway.

```python
#!/usr/bin/env python3
"""
Generate pruned lexicon from:
1. Original en.dic filtered to only words in LM
2. Generated pronunciations for LM words not in en.dic
3. New domain words from extra.txt
"""
import phonetisaurus
import sys
import gzip

# First, load LM vocabulary to know what words to keep
lm_words = set()
lm_file = 'data/lgraph-base.lm.gz'
print(f'Loading LM vocabulary from {lm_file}...', file=sys.stderr, flush=True)

with gzip.open(lm_file, 'rt') as f:
    in_unigrams = False
    for line in f:
        line = line.strip()
        if line == '\\1-grams:':
            in_unigrams = True
            continue
        elif line.startswith('\\') and line.endswith(':'):
            if in_unigrams:
                break
            continue
        if in_unigrams and line:
            parts = line.split('\t')
            if len(parts) >= 2:
                word = parts[1]
                if not word.startswith('<'):
                    lm_words.add(word)

print(f'LM vocabulary: {len(lm_words)} words', file=sys.stderr, flush=True)

words = {}

# Load original lexicon, but only keep words in LM
skipped = 0
for line in open('db/en.dic'):
    items = line.split()
    word = items[0]
    base_word = word.split('(')[0] if '(' in word else word

    if base_word not in lm_words:
        skipped += 1
        continue

    if word not in words:
        words[word] = []
    words[word].append(' '.join(items[1:]))

print(f'Loaded {len(words)} words from en.dic (skipped {skipped} not in LM)', file=sys.stderr)

# Load extra.dic if exists (domain-specific, always include)
try:
    for line in open('db/extra.dic'):
        items = line.split()
        if items[0] not in words:
            words[items[0]] = []
        words[items[0]].append(' '.join(items[1:]))
except:
    pass

# Load generated pronunciations for LM words not in dictionary
for line in open('missing_pronunciations.txt'):
    items = line.split()
    if items[0] not in words:
        words[items[0]] = []
    words[items[0]].append(' '.join(items[1:]))

print(f'After adding missing words: {len(words)} words', file=sys.stderr)

# Generate pronunciations for new domain words
new_words = set()
for line in open('db/extra.txt'):
    for w in line.split():
        if w not in words:
            new_words.add(w)

if new_words:
    print(f'Generating pronunciations for {len(new_words)} new domain words', file=sys.stderr)
    for w, phones in phonetisaurus.predict(new_words, 'db/en-g2p/en.fst'):
        words[w] = []
        words[w].append(' '.join(phones))

print(f'Final lexicon: {len(words)} words', file=sys.stderr)

for w, phones in sorted(words.items()):
    for p in phones:
        print(w, p)
```

### 5. Create compile-lgraph.sh

```bash
#!/bin/bash
set -ex
cd ~/vosk-lgraph-compile

export PATH=$HOME/miniconda3/bin:$PATH
export LD_LIBRARY_PATH=$HOME/miniconda3/lib:$HOME/miniconda3/lib/fst:$LD_LIBRARY_PATH

rm -rf data/dict data/lang data/lang_local exp/chain/tdnn/lgraph

echo "=== Step 1: Dictionary ==="
mkdir -p data/dict
cp db/phone/* data/dict/
$HOME/miniconda3/bin/python3 dict-pruned.py > data/dict/lexicon.txt

echo "=== Step 2: prepare_lang.sh ==="
podman run --rm -v $HOME/vosk-lgraph-compile:/work -w /work docker.io/kaldiasr/kaldi:latest bash -c '
    export PATH=/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/src/fstbin:/opt/kaldi/src/bin:/opt/kaldi/egs/wsj/s5/utils:$PATH
    export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/src/lib:$LD_LIBRARY_PATH
    utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang
'

echo "=== Step 3: Build Gr.fst ==="
gunzip -c data/lgraph-base.lm.gz | \
    ngramread --ARPA --symbols=data/lang/words.txt --OOV_symbol="[unk]" - | \
    fstarcsort --sort_type=ilabel > data/Gr.fst

echo "=== Step 4: HCLr.fst with lookahead ==="
podman run --rm -v $HOME/vosk-lgraph-compile:/work -w /work docker.io/kaldiasr/kaldi:latest bash -c '
    set -ex
    export PATH=/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/src/fstbin:/opt/kaldi/src/bin:/opt/kaldi/egs/wsj/s5/utils:$PATH
    export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/tools/openfst-1.8.4/lib/fst:/opt/kaldi/src/lib:$LD_LIBRARY_PATH

    tree=exp/chain/tdnn/tree
    model=exp/chain/tdnn/final.mdl
    lang=data/lang
    dir=exp/chain/tdnn/lgraph

    rm -rf $dir && mkdir -p $dir/phones
    cp $lang/phones.txt $dir/
    cp $lang/phones/* $dir/phones/

    fstdeterminizestar --use-log=true < $lang/L_disambig.fst > $dir/L_disambig_det.fst

    fstcomposecontext --context-size=2 --central-position=1 \
        --read-disambig-syms=$lang/phones/disambig.int \
        --write-disambig-syms=$dir/disambig_ilabels.int \
        $dir/ilabels < $dir/L_disambig_det.fst | fstarcsort --sort_type=ilabel > $dir/CLG.fst

    make-h-transducer --disambig-syms-out=$dir/disambig_tid.int \
        --transition-scale=1.0 $dir/ilabels $tree $model > $dir/Ha.fst

    fsttablecompose $dir/Ha.fst $dir/CLG.fst | \
        fstdeterminizestar --use-log=true | \
        fstrmsymbols $dir/disambig_tid.int | \
        fstrmepslocal | \
        fstminimizeencoded | \
        add-self-loops --self-loop-scale=1.0 --reorder=true $model | \
        fstarcsort --sort_type=olabel | \
        fstconvert --fst_type=olabel_lookahead --save_relabel_opairs=$dir/relabel > $dir/HCLr.fst

    rm -f $dir/Ha.fst $dir/CLG.fst $dir/L_disambig_det.fst $dir/ilabels

    utils/apply_map.pl --permissive -f 2 $dir/relabel < $lang/words.txt > $dir/words.txt

    fstrelabel --relabel_ipairs=$dir/relabel data/Gr.fst | \
        fstarcsort --sort_type=ilabel | \
        fstconvert --fst_type=const > $dir/Gr.fst
'

echo "=== Complete ==="
ls -lh exp/chain/tdnn/lgraph/
```

## Adding New Domain Words

### 1. Edit db/extra.txt on GPU host

Add your domain-specific text. Words not in the lexicon will have pronunciations generated automatically:

```bash
ssh john@gpu "cat >> ~/vosk-lgraph-compile/db/extra.txt << 'EOF'
your domain specific words and phrases here
technical terms product names etc
EOF"
```

### 2. (Optional) Add manual pronunciations

For words where G2P might fail, add to `db/extra.dic`:

```bash
ssh john@gpu "cat >> ~/vosk-lgraph-compile/db/extra.dic << 'EOF'
myword m aI w 3` d
EOF"
```

### 3. Rebuild

```bash
ssh john@gpu "cd ~/vosk-lgraph-compile && ./compile-lgraph.sh"
```

### 4. Copy to local machine

```bash
rm -rf ~/Downloads/vosk-model-en-us-0.22-lgraph-custom/graph
mkdir -p ~/Downloads/vosk-model-en-us-0.22-lgraph-custom/graph
scp -r john@gpu:~/vosk-lgraph-compile/exp/chain/tdnn/lgraph/* \
    ~/Downloads/vosk-model-en-us-0.22-lgraph-custom/graph/

# Copy acoustic model files if not already present
cp -r ~/Downloads/vosk-model-en-us-0.22-lgraph/{am,ivector,conf,README} \
    ~/Downloads/vosk-model-en-us-0.22-lgraph-custom/
```

## Output Files

The build produces:

| File | Size | Description |
|------|------|-------------|
| HCLr.fst | ~27MB | Lexicon/acoustic graph (olabel_lookahead format) |
| Gr.fst | ~80MB | Language model (const format) |
| words.txt | ~3.5MB | Vocabulary (~232k words, pruned to LM) |
| phones.txt | ~2KB | Phone symbols |
| phones/ | - | Phone definitions |

## Troubleshooting

### Model produces garbage output

Check that HCLr.fst has the correct FST type:
```bash
file ~/Downloads/vosk-model-en-us-0.22-lgraph-custom/graph/HCLr.fst
# Should show: fst type: olabel_lookahead
```

If it shows `fst type: vector`, the lookahead conversion failed.

### Missing words

Check the lexicon was generated correctly:
```bash
grep "yourword" ~/Downloads/vosk-model-en-us-0.22-lgraph-custom/graph/words.txt
```

### Container errors

Ensure the Kaldi container has the lookahead FST library:
```bash
podman run --rm docker.io/kaldiasr/kaldi:latest \
    ls /opt/kaldi/tools/openfst-1.8.4/lib/fst/olabel_lookahead-fst.so
```

## References

- [Vosk LM Documentation](https://alphacephei.com/vosk/lm)
- [Vosk Model Adaptation](https://alphacephei.com/vosk/adaptation)
- [Kaldi mkgraph_lookahead.sh](https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/utils/mkgraph_lookahead.sh)
