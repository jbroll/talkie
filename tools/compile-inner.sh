#!/bin/bash
# This script runs inside the kaldi-opengrm container.
set -ex

# Setup paths.
#
# IMPORTANT: Kaldi's OpenFST must come BEFORE miniforge in PATH/
# LD_LIBRARY_PATH. Both trees install fstarcsort/fstconvert/etc., but
# conda's OpenFST is a different build than Kaldi's openfst-1.8.4; mixing
# them produces FSTs that validate_lang.pl rejects as "not olabel sorted"
# and that later steps silently miscompile. miniforge only needs to
# provide ngramread/ngramprint (no Kaldi equivalent).
export PATH=/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/src/fstbin:/opt/kaldi/src/bin:/opt/kaldi/src/lmbin:/opt/kaldi/egs/wsj/s5/utils:/opt/miniforge/bin:$PATH
export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/tools/openfst-1.8.4/lib/fst:/opt/kaldi/src/lib:/opt/miniforge/lib:$LD_LIBRARY_PATH

cd /model/compile

# Symlink Kaldi utils so prepare_lang.sh's relative lookups work.
ln -sf /opt/kaldi/egs/wsj/s5/utils utils
ln -sf /opt/kaldi/egs/wsj/s5/steps steps

# validate_lang.pl sources ./path.sh in every subshell check it does
# (olabel-sort, word_boundary reconstruction, G.fst ilabel, ...). If the
# file is missing every check false-positives because the compound
# ". ./path.sh; <cmd>" exits non-zero before $cmd runs. Ship a stub.
cat > path.sh <<PATHSH
export PATH=$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH
PATHSH

# Clean previous build artifacts
rm -rf data/dict data/lang data/lang_local build

echo "=== Step 1: Generate Dictionary ==="
mkdir -p data/dict
cp db/phone/* data/dict/
python3 dict-pruned.py > data/dict/lexicon.txt

echo "=== Step 2: prepare_lang.sh ==="
./utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang

echo "=== Step 3a: Build domain LM from db/extra.txt ==="
# extra.txt holds context sentences for our domain vocabulary. Without
# this step the domain words land in the lexicon (L.fst) but the LM
# treats them as OOV and maps them to [unk], so the decoder effectively
# never picks them. We build a small n-gram LM from the contexts and
# interpolate it with the base LM so the domain words have real
# probabilities in context.
LM_ORDER=4
LM_ALPHA=0.95  # weight of base LM; (1-alpha)=0.05 goes to the domain LM

# Compile text into a FAR in the lexicon's symbol space. Tokens not in
# words.txt get mapped to [unk] (same symbol the LM uses for OOV).
farcompilestrings --token_type=symbol \
    --symbols=data/lang/words.txt \
    --unknown_symbol='[unk]' \
    --keep_symbols \
    db/extra.txt data/domain.far

ngramcount --order=$LM_ORDER data/domain.far data/domain.counts.fst
ngrammake --method=witten_bell data/domain.counts.fst data/domain.lm.fst

echo "=== Step 3b: Interpolate domain LM with base LM ==="
# Read base ARPA into an FST in the same symbol space.
gunzip -c lgraph-base.lm.gz | \
    ngramread --ARPA --symbols=data/lang/words.txt --OOV_symbol="[unk]" - \
    > data/base.lm.fst

# model_merge is linear interpolation: --alpha weights the first FST
# (base) and --beta weights the second (domain). alpha=0.95 beta=0.05
# is 95% base / 5% domain, matching the SRILM --lambda that built lm-test.
LM_BETA=$(python3 -c "print(1.0 - $LM_ALPHA)")
ngrammerge --method=model_merge \
    --alpha=$LM_ALPHA --beta=$LM_BETA \
    --ofile=data/mixed.lm.fst \
    data/base.lm.fst data/domain.lm.fst
fstarcsort --sort_type=ilabel data/mixed.lm.fst > data/Gr.fst

echo "=== Step 4: Build HCLr.fst with lookahead ==="
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

./utils/apply_map.pl --permissive -f 2 $dir/relabel < $lang/words.txt > $dir/words.txt

fstrelabel --relabel_ipairs=$dir/relabel data/Gr.fst | \
    fstarcsort --sort_type=ilabel | \
    fstconvert --fst_type=const > $dir/Gr.fst

echo "=== Build Complete ==="
