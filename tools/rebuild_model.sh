#!/bin/bash
#
# rebuild_model.sh - Build custom Vosk model with domain vocabulary
#
# Usage: ./rebuild_model.sh [CORPUS_DIRS...]
#
# Example:
#   ./rebuild_model.sh ~/src ~/docs
#   ./rebuild_model.sh  # Uses current directory
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KALDI_ROOT="${KALDI_ROOT:-$HOME/kaldi}"
BASE_MODEL="${BASE_MODEL:-$HOME/Downloads/vosk-model-en-us-0.22-lgraph}"
COMPILE_PKG="${COMPILE_PKG:-$HOME/Downloads/vosk-model-en-us-0.22-compile}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/models/vosk-custom-lgraph}"
BUILD_DIR="${BUILD_DIR:-/tmp/vosk-build-$$}"

# LM parameters
LM_ORDER=4
LM_LAMBDA=0.95      # 95% base LM, 5% domain LM
LM_PRUNE=3e-8       # Pruning threshold

# Corpus directories (from command line or default)
if [ $# -gt 0 ]; then
    CORPUS_DIRS=("$@")
else
    CORPUS_DIRS=("$(pwd)")
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $1" >&2; exit 1; }

# Check prerequisites
check_prereqs() {
    log "Checking prerequisites..."

    [ -d "$KALDI_ROOT/src/bin" ] || error "Kaldi not found at $KALDI_ROOT"
    [ -d "$BASE_MODEL/graph" ] || error "Base model not found at $BASE_MODEL"
    [ -d "$COMPILE_PKG/utils" ] || error "Compile package not found at $COMPILE_PKG"
    [ -f "$SCRIPT_DIR/base_missing.dic" ] || error "base_missing.dic not found (run generate_missing_pronunciations.py)"
    [ -x "$SCRIPT_DIR/extract_vocabulary.py" ] || error "extract_vocabulary.py not found"
    [ -x "$SCRIPT_DIR/arpa_interpolate.py" ] || error "arpa_interpolate.py not found"
    [ -x "$SCRIPT_DIR/arpa_prune.py" ] || error "arpa_prune.py not found"
    python3 -c "import phonetisaurus" 2>/dev/null || error "phonetisaurus not installed (pip install phonetisaurus)"

    log "All prerequisites met"
}

# Set up environment
setup_env() {
    export PATH="$KALDI_ROOT/src/bin:$KALDI_ROOT/src/fstbin:$KALDI_ROOT/src/lmbin:$KALDI_ROOT/tools/openfst/bin:$PATH"
    export LD_LIBRARY_PATH="$KALDI_ROOT/tools/openfst/lib:$KALDI_ROOT/tools/OpenBLAS/install/lib:$KALDI_ROOT/src/lib:$LD_LIBRARY_PATH"

    mkdir -p "$BUILD_DIR"
    log "Build directory: $BUILD_DIR"
}

# Step 1: Extract vocabulary from corpus
extract_vocabulary() {
    log "Step 1: Extracting vocabulary from corpus..."

    "$SCRIPT_DIR/extract_vocabulary.py" \
        --model "$BASE_MODEL" \
        --output "$BUILD_DIR" \
        --min-occurrences 5 \
        --max-length 20 \
        --max-hyphens 1 \
        "${CORPUS_DIRS[@]}"

    local word_count=$(wc -l < "$BUILD_DIR/missing_words.txt" 2>/dev/null || echo 0)
    log "Found $word_count domain-specific words"

    if [ "$word_count" -eq 0 ]; then
        warn "No new vocabulary found. Model unchanged."
        exit 0
    fi
}

# Step 2: Build domain language model
build_domain_lm() {
    log "Step 2: Building domain language model..."

    local context_file="$BUILD_DIR/extra_contexts.txt"
    [ -s "$context_file" ] || error "No context sentences found"

    # Use Kaldi's make_kn_lm.py
    python3 "$KALDI_ROOT/egs/wsj/s5/utils/lang/make_kn_lm.py" \
        -ngram-order "$LM_ORDER" \
        -text "$context_file" \
        -lm "$BUILD_DIR/domain.lm"

    log "Domain LM built: $BUILD_DIR/domain.lm"
}

# Step 3: Interpolate with base LM
interpolate_lm() {
    log "Step 3: Interpolating with base LM (lambda=$LM_LAMBDA)..."

    local base_lm="$COMPILE_PKG/db/en-230k-0.5.lm.gz"
    [ -f "$base_lm" ] || error "Base LM not found: $base_lm"

    "$SCRIPT_DIR/arpa_interpolate.py" \
        --lm "$base_lm" \
        --mix-lm "$BUILD_DIR/domain.lm" \
        --lambda "$LM_LAMBDA" \
        --output "$BUILD_DIR/mixed.lm.gz"

    log "Interpolated LM: $BUILD_DIR/mixed.lm.gz"
}

# Step 4: Prune language model
prune_lm() {
    log "Step 4: Pruning language model (threshold=$LM_PRUNE)..."

    "$SCRIPT_DIR/arpa_prune.py" \
        --lm "$BUILD_DIR/mixed.lm.gz" \
        --threshold "$LM_PRUNE" \
        --output "$BUILD_DIR/final.lm.gz"

    local size=$(du -h "$BUILD_DIR/final.lm.gz" | cut -f1)
    log "Final LM: $BUILD_DIR/final.lm.gz ($size)"
}

# Step 5: Prepare lexicon
prepare_lexicon() {
    log "Step 5: Preparing lexicon..."

    # Copy phone definitions
    mkdir -p "$BUILD_DIR/dict"
    cp "$COMPILE_PKG/db/phone/"* "$BUILD_DIR/dict/"

    # Merge dictionaries:
    #   1. en.dic (312k words from compile package)
    #   2. base_missing.dic (56k words from lgraph not in en.dic)
    #   3. extra.dic (domain words from corpus scan)
    log "  Merging dictionaries..."
    log "    - en.dic: $(wc -l < "$COMPILE_PKG/db/en.dic") entries"
    log "    - base_missing.dic: $(wc -l < "$SCRIPT_DIR/base_missing.dic") entries"
    log "    - extra.dic: $(wc -l < "$BUILD_DIR/extra.dic" 2>/dev/null || echo 0) entries"

    cat "$COMPILE_PKG/db/en.dic" \
        "$SCRIPT_DIR/base_missing.dic" \
        "$BUILD_DIR/extra.dic" 2>/dev/null | \
        sort -u > "$BUILD_DIR/dict/lexicon.txt"

    local total=$(wc -l < "$BUILD_DIR/dict/lexicon.txt")
    log "Lexicon prepared: $total words (should be ~368k + domain words)"
}

# Step 6: Build FST graph with Kaldi
build_graph() {
    log "Step 6: Building FST graph..."

    cd "$COMPILE_PKG"

    # Clean previous build
    rm -rf data/dict data/lang data/lang_local data/lang_test exp/chain/tdnn/lgraph

    # Copy our files
    mkdir -p data/dict
    cp "$BUILD_DIR/dict/"* data/dict/

    # Prepare lang directory
    utils/prepare_lang.sh data/dict "[unk]" data/lang_local data/lang

    # Format LM
    utils/format_lm.sh data/lang "$BUILD_DIR/final.lm.gz" data/dict/lexicon.txt data/lang_test

    # Build lookahead graph
    utils/mkgraph_lookahead.sh \
        --self-loop-scale 1.0 \
        data/lang exp/chain/tdnn "$BUILD_DIR/final.lm.gz" exp/chain/tdnn/lgraph

    log "Graph built: $COMPILE_PKG/exp/chain/tdnn/lgraph/"
}

# Step 7: Assemble output model
assemble_model() {
    log "Step 7: Assembling output model..."

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    # Copy acoustic model (unchanged)
    cp -r "$BASE_MODEL/am" "$OUTPUT_DIR/"
    cp -r "$BASE_MODEL/conf" "$OUTPUT_DIR/"
    cp -r "$BASE_MODEL/ivector" "$OUTPUT_DIR/"

    # Copy new graph
    cp -r "$COMPILE_PKG/exp/chain/tdnn/lgraph" "$OUTPUT_DIR/graph"

    # Create manifest
    cat > "$OUTPUT_DIR/manifest.json" << EOF
{
    "base_model": "$BASE_MODEL",
    "build_date": "$(date -Iseconds)",
    "corpus_dirs": $(printf '%s\n' "${CORPUS_DIRS[@]}" | jq -R . | jq -s .),
    "new_words": $(wc -l < "$BUILD_DIR/missing_words.txt"),
    "lm_lambda": $LM_LAMBDA,
    "lm_prune": "$LM_PRUNE"
}
EOF

    local size=$(du -sh "$OUTPUT_DIR" | cut -f1)
    log "Output model: $OUTPUT_DIR ($size)"
}

# Cleanup
cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        log "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
}

# Main
main() {
    log "=== Vosk Custom Model Builder ==="
    log "Corpus: ${CORPUS_DIRS[*]}"
    log "Output: $OUTPUT_DIR"
    echo

    check_prereqs
    setup_env

    trap cleanup EXIT

    extract_vocabulary
    build_domain_lm
    interpolate_lm
    prune_lm
    prepare_lexicon
    build_graph
    assemble_model

    echo
    log "=== Build Complete ==="
    log "Test with: vosk-transcriber -m $OUTPUT_DIR"
}

main "$@"
