#!/bin/bash
set -ex

cd ~/vosk-compile

# Run compilation inside Kaldi container
podman run --rm -v ~/vosk-compile:/work -v ~/vosk-tools:/tools -w /work docker.io/kaldiasr/kaldi:latest bash -c '
set -ex

export PATH=/tools:/opt/kaldi/src/fstbin:/opt/kaldi/src/bin:/opt/kaldi/src/lmbin:/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/egs/wsj/s5/utils:$PATH
export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/src/lib:$LD_LIBRARY_PATH

# Step 1: Build LMs (ngram-count, interpolate, prune)
echo "=== Building language models ==="
ngram-count -wbdiscount -order 4 -text db/extra.txt -lm data/extra.lm.gz

echo "=== Interpolating LMs ==="
ngram -order 4 -lm db/en-230k-0.5.lm.gz -mix-lm data/extra.lm.gz -lambda 0.95 -write-lm data/en-mix.lm.gz

echo "=== Pruning LM ==="
ngram -order 4 -lm data/en-mix.lm.gz -prune 3e-8 -write-lm data/en-mix-small.lm.gz

# Step 2: prepare_lang.sh (rebuild to be safe)
echo "=== Running prepare_lang.sh ==="
rm -rf data/lang_local data/lang
utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang

# Step 3: format_lm.sh
echo "=== Running format_lm.sh ==="
rm -rf data/lang_test
utils/format_lm.sh data/lang data/en-mix-small.lm.gz data/dict/lexicon.txt data/lang_test

# Step 4: mkgraph.sh (requires exp/chain/tdnn model)
echo "=== Running mkgraph.sh ==="
if [ -d exp/chain/tdnn ]; then
    rm -rf exp/chain/tdnn/graph
    utils/mkgraph.sh --self-loop-scale 1.0 data/lang_test exp/chain/tdnn exp/chain/tdnn/graph
else
    echo "WARNING: exp/chain/tdnn not found, skipping mkgraph.sh"
fi

echo "=== Done ==="
'
