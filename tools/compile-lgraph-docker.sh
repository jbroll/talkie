#!/bin/bash
# Rebuild the lgraph model with updated vocabulary, using the
# kaldi-opengrm container for the whole pipeline.
#
# Prerequisites:
#   - Docker image kaldi-opengrm (see tools/kaldi-opengrm.Dockerfile)
#   - lgraph-base.lm.gz and missing_pronunciations.txt already present in
#     compile/ (one-time extract from the shipped Gr.fst)
#   - db/extra.txt + db/extra.dic with the domain vocabulary
#
# Run from the compile/ directory:
#   ./compile-lgraph-docker.sh

set -ex
cd "$(dirname "$0")"
MODEL_ROOT=$(cd .. && pwd)

# Sanity check: refuse to install a stale build/ as a "new" graph.
# Without this the install step silently copies whatever happens to be
# in build/ from a previous run.
if [ ! -f ./compile-inner.sh ]; then
    echo "ERROR: compile-inner.sh missing from $(pwd)" >&2
    exit 1
fi
rm -rf build

# Run the inner script inside the container. compile-inner.sh is bind-mounted
# from the host at /model/compile/compile-inner.sh. Invoking it as an
# argument (not via stdin heredoc) avoids the "docker run without -i
# discards stdin" trap that silently skipped the build in an earlier rev.
#
# --user runs as the host user so build artifacts don't end up root-owned
# on the bind-mounted volume. This requires phonetisaurus to be baked
# into the image (see tools/kaldi-opengrm.Dockerfile); rebuild the image
# if you get ModuleNotFoundError for phonetisaurus.
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$MODEL_ROOT":/model \
    -w /model/compile \
    kaldi-opengrm \
    bash -e compile-inner.sh

echo "=== Step 5: Install to graph/ ==="
[ -f build/HCLr.fst ] || { echo "ERROR: build/HCLr.fst not produced" >&2; exit 1; }
[ -f build/Gr.fst   ] || { echo "ERROR: build/Gr.fst not produced"   >&2; exit 1; }

if [ -d ../graph.bak ]; then
    rm -rf ../graph.bak
fi
if [ -d ../graph ]; then
    mv ../graph ../graph.bak
fi

mkdir -p ../graph/phones
cp build/HCLr.fst build/Gr.fst build/words.txt build/phones.txt ../graph/
cp build/phones/* ../graph/phones/
cp build/disambig_tid.int ../graph/ 2>/dev/null || true

echo "=== Complete ==="
echo "New graph installed to ../graph/"
echo "Previous graph backed up to ../graph.bak/"
ls -lh ../graph/
