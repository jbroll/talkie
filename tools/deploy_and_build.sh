#!/bin/bash
#
# deploy_and_build.sh - Extract vocabulary locally, build model on GPU host
#
# Usage:
#   ./deploy_and_build.sh [CORPUS_DIRS...]
#
# Example:
#   ./deploy_and_build.sh ~/src ~/docs
#   ./deploy_and_build.sh ~/src/talkie
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GPU_HOST="${GPU_HOST:-john@gpu}"
GPU_WORK_DIR="${GPU_WORK_DIR:-~/vosk-build}"
LOCAL_BUILD_DIR="/tmp/vosk-vocab-$$"

# Corpus directories (from command line or default)
if [ $# -gt 0 ]; then
    CORPUS_DIRS=("$@")
else
    CORPUS_DIRS=("$(pwd)")
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[LOCAL]${NC} $1"; }
warn() { echo -e "${YELLOW}[LOCAL] WARNING:${NC} $1"; }
error() { echo -e "${RED}[LOCAL] ERROR:${NC} $1" >&2; exit 1; }

# Step 1: Extract vocabulary locally
extract_vocab() {
    log "Step 1: Extracting vocabulary from corpus..."

    mkdir -p "$LOCAL_BUILD_DIR"

    "$SCRIPT_DIR/extract_vocabulary.py" \
        --output "$LOCAL_BUILD_DIR" \
        --min-occurrences 5 \
        --max-length 20 \
        --max-hyphens 1 \
        "${CORPUS_DIRS[@]}"

    local word_count=$(wc -l < "$LOCAL_BUILD_DIR/missing_words.txt" 2>/dev/null || echo 0)
    log "Found $word_count domain-specific words"

    if [ "$word_count" -eq 0 ]; then
        warn "No new vocabulary found."
        rm -rf "$LOCAL_BUILD_DIR"
        exit 0
    fi

    log "Files created in $LOCAL_BUILD_DIR:"
    ls -la "$LOCAL_BUILD_DIR/"
}

# Step 2: Deploy files to GPU host
deploy_files() {
    log "Step 2: Deploying files to $GPU_HOST..."

    # Create work directory on GPU host
    ssh "$GPU_HOST" "mkdir -p $GPU_WORK_DIR/vocab"

    # Copy vocabulary files
    scp "$LOCAL_BUILD_DIR/extra.dic" \
        "$LOCAL_BUILD_DIR/extra_contexts.txt" \
        "$LOCAL_BUILD_DIR/missing_words.txt" \
        "$GPU_HOST:$GPU_WORK_DIR/vocab/"

    # Copy build script and base_missing.dic if not already there
    ssh "$GPU_HOST" "[ -f $GPU_WORK_DIR/rebuild_model_gpu.sh ] || echo 'need scripts'"
    scp "$SCRIPT_DIR/rebuild_model_gpu.sh" \
        "$SCRIPT_DIR/base_missing.dic" \
        "$GPU_HOST:$GPU_WORK_DIR/"

    log "Files deployed to $GPU_HOST:$GPU_WORK_DIR/"
}

# Step 3: Run build on GPU host
run_remote_build() {
    log "Step 3: Running build on GPU host..."

    ssh -t "$GPU_HOST" "cd $GPU_WORK_DIR && chmod +x rebuild_model_gpu.sh && ./rebuild_model_gpu.sh vocab"
}

# Step 4: Fetch result (optional)
fetch_result() {
    local output_dir="${1:-$HOME/models/vosk-custom-lgraph}"

    log "Step 4: Fetching model from GPU host..."

    mkdir -p "$output_dir"
    scp -r "$GPU_HOST:~/models/vosk-custom-lgraph/*" "$output_dir/"

    log "Model saved to: $output_dir"
}

# Cleanup
cleanup() {
    if [ -d "$LOCAL_BUILD_DIR" ]; then
        rm -rf "$LOCAL_BUILD_DIR"
    fi
}

# Main
main() {
    log "=== Vosk Model Build (Local + GPU) ==="
    log "Corpus: ${CORPUS_DIRS[*]}"
    log "GPU Host: $GPU_HOST"
    echo

    trap cleanup EXIT

    extract_vocab
    deploy_files
    run_remote_build

    echo
    log "=== Build Complete ==="
    log "Model on GPU host at: ~/models/vosk-custom-lgraph"
    log "To fetch locally: scp -r $GPU_HOST:~/models/vosk-custom-lgraph ~/models/"
}

main "$@"
