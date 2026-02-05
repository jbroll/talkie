#!/bin/bash
# Rebuild the lgraph model with updated vocabulary
#
# Prerequisites:
#   - Container runtime (podman or docker) with Kaldi image:
#       podman pull docker.io/kaldiasr/kaldi:latest
#   - Miniforge/Miniconda with OpenGRM NGram tools:
#       conda install -c conda-forge ngram
#       pip install phonetisaurus
#   - lgraph-base.lm.gz extracted from original Gr.fst (one-time, see README)
#
# Run from the compile/ directory:
#   ./compile-lgraph.sh
#
# Environment variables:
#   CONTAINER_CMD - container runtime (default: podman, or docker)
#   CONDA_PREFIX  - conda environment prefix (default: ~/miniforge3)

set -ex
cd "$(dirname "$0")"

# Container runtime (podman on local, docker on GPU host)
CONTAINER_CMD="${CONTAINER_CMD:-podman}"
if ! command -v "$CONTAINER_CMD" &>/dev/null; then
    if command -v docker &>/dev/null; then
        CONTAINER_CMD=docker
    elif command -v podman &>/dev/null; then
        CONTAINER_CMD=podman
    else
        echo "ERROR: Neither podman nor docker found" >&2
        exit 1
    fi
fi

# Conda paths for OpenFST tools (ngramread, fstarcsort, etc.)
CONDA_PREFIX="${CONDA_PREFIX:-$HOME/miniforge3}"
if [ ! -d "$CONDA_PREFIX" ]; then
    # Fall back to miniconda3
    CONDA_PREFIX="$HOME/miniconda3"
fi
export PATH="$CONDA_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}"

# Verify required tools
for tool in ngramread fstarcsort python3; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: $tool not found. Install with: conda install -c conda-forge ngram" >&2
        exit 1
    fi
done

# Clean previous build artifacts
rm -rf data/dict data/lang data/lang_local build

# Get absolute path to model root (parent of compile/)
MODEL_ROOT=$(cd .. && pwd)

echo "=== Step 1: Generate Dictionary ==="
mkdir -p data/dict
cp db/phone/* data/dict/
python3 dict-pruned.py > data/dict/lexicon.txt
echo "Generated lexicon with $(wc -l < data/dict/lexicon.txt) entries"

echo "=== Step 2: prepare_lang.sh ==="
$CONTAINER_CMD run --rm -v "$MODEL_ROOT":/model -w /model/compile docker.io/kaldiasr/kaldi:latest bash -c '
set -e
export PATH=/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/src/fstbin:/opt/kaldi/src/bin:/opt/kaldi/egs/wsj/s5/utils:$PATH
export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/src/lib:$LD_LIBRARY_PATH

# Create symlinks to Kaldi utilities
ln -sf /opt/kaldi/egs/wsj/s5/utils utils
ln -sf /opt/kaldi/egs/wsj/s5/steps steps

./utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang
'

echo "=== Step 3: Build Gr.fst ==="
gunzip -c lgraph-base.lm.gz | \
    ngramread --ARPA --symbols=data/lang/words.txt --OOV_symbol="[unk]" - | \
    fstarcsort --sort_type=ilabel > data/Gr.fst
echo "Built Gr.fst: $(ls -lh data/Gr.fst | awk '{print $5}')"

echo "=== Step 4: Build HCLr.fst with lookahead ==="
$CONTAINER_CMD run --rm -v "$MODEL_ROOT":/model -w /model/compile docker.io/kaldiasr/kaldi:latest bash -ex -c '
export PATH=/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/src/fstbin:/opt/kaldi/src/bin:/opt/kaldi/egs/wsj/s5/utils:$PATH
export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/tools/openfst-1.8.4/lib/fst:/opt/kaldi/src/lib:$LD_LIBRARY_PATH

tree=/model/am/tree
model=/model/am/final.mdl
lang=data/lang
dir=build

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

apply_map.pl --permissive -f 2 $dir/relabel < $lang/words.txt > $dir/words.txt

fstrelabel --relabel_ipairs=$dir/relabel data/Gr.fst | \
    fstarcsort --sort_type=ilabel | \
    fstconvert --fst_type=const > $dir/Gr.fst
'

echo "=== Step 5: Install to graph/ ==="
# Backup existing graph
if [ -d ../graph.bak ]; then
    rm -rf ../graph.bak
fi
if [ -d ../graph ]; then
    mv ../graph ../graph.bak
fi

# Install new graph
mkdir -p ../graph/phones
cp build/HCLr.fst build/Gr.fst build/words.txt build/phones.txt ../graph/
cp build/phones/* ../graph/phones/
cp build/disambig_tid.int ../graph/ 2>/dev/null || true

echo "=== Complete ==="
echo "New graph installed to ../graph/"
echo "Previous graph backed up to ../graph.bak/"
echo ""
echo "Output files:"
ls -lh ../graph/
echo ""
echo "Vocabulary: $(wc -l < ../graph/words.txt) words"
echo "HCLr.fst type: $(file ../graph/HCLr.fst | grep -o 'fst type: [^,]*')"
