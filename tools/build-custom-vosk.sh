#!/bin/bash
#
# build-custom-vosk.sh — End-to-end custom Vosk model build.
#
# Stateless remote: the only things gpu must have are ssh access, docker,
# and the kaldi-opengrm:latest image. Everything else — the base model
# inputs, the compile scripts, today's vocabulary — is rsync'd from the
# local repo into a temporary work directory per build, and cleaned up
# after the graph is fetched back.
#
# Flow:
#   1. extract_vocabulary.py scans corpus dirs for .md/.txt, filters
#      noise, runs phonetisaurus G2P. Emits extra.txt + extra.dic.
#   2. rsync the base model compile inputs, the scripts, and the new
#      vocab into GPU_WORK_DIR/vosk-build/ on the remote.
#   3. Run compile-lgraph-docker.sh inside the kaldi-opengrm container
#      on gpu (as host uid/gid — no root-owned leftovers).
#   4. rsync graph/ back; assemble the new model dir locally with local
#      am/, conf/, ivector/ (unchanged across builds) plus the fresh
#      graph/. Date-stamp the dir.
#   5. Optionally (--switch) flip vosk_modelfile in ~/.config/talkie.conf.
#      talkie's filewatch picks it up within ~1s and hot-swaps the
#      engine.
#   6. Remove the remote work dir.
#
# Usage:
#   ./build-custom-vosk.sh [CORPUS_DIRS...] [--switch] [--date YYYY-MM-DD]
#                          [--keep-remote]
#
# Defaults: corpus = ~/src, ~/Documents, ~/notes (whichever exist).
#
# Environment:
#   GPU_HOST      ssh alias for the build host (default: gpu)
#   GPU_WORK_DIR  remote work dir (default: ~/vosk-build-tmp)
#   BASE_MODEL    local base model (default: models/vosk/vosk-model-en-us-0.22-lgraph)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

GPU_HOST=${GPU_HOST:-gpu}
GPU_WORK_DIR=${GPU_WORK_DIR:-'~/vosk-build-tmp'}
BASE_MODEL=${BASE_MODEL:-"$REPO_ROOT/models/vosk/vosk-model-en-us-0.22-lgraph"}
MODELS_DIR="$REPO_ROOT/models/vosk"

SWITCH=0
KEEP_REMOTE=0
DATE=$(date +%Y-%m-%d)
CORPUS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --switch)      SWITCH=1; shift ;;
        --keep-remote) KEEP_REMOTE=1; shift ;;
        --date)        DATE=$2; shift 2 ;;
        --help|-h)
            sed -n '3,36p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)  CORPUS+=("$1"); shift ;;
    esac
done

if [ ${#CORPUS[@]} -eq 0 ]; then
    for d in "$HOME/src" "$HOME/Documents" "$HOME/notes"; do
        [ -d "$d" ] && CORPUS+=("$d")
    done
fi
if [ ${#CORPUS[@]} -eq 0 ]; then
    echo "no corpus directories: pass some on the command line or create ~/src, ~/Documents, ~/notes" >&2
    exit 2
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[%s]${NC} %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "${YELLOW}[%s] WARN:${NC} %s\n" "$(date +%H:%M:%S)" "$*"; }
die()  { printf "${RED}[%s] ERROR:${NC} %s\n" "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# Preflight checks.
[ -d "$BASE_MODEL" ]                                || die "base model not found: $BASE_MODEL"
[ -f "$BASE_MODEL/graph/words.txt" ]                || die "missing words.txt in $BASE_MODEL/graph"
[ -d "$BASE_MODEL/am" ]                             || die "missing am/ in $BASE_MODEL"
[ -d "$BASE_MODEL/compile/db" ]                     || die "missing compile/db/ in $BASE_MODEL"
[ -f "$BASE_MODEL/compile/lgraph-base.lm.gz" ]      || die "missing compile/lgraph-base.lm.gz in $BASE_MODEL"
[ -f "$BASE_MODEL/compile/missing_pronunciations.txt" ] || die "missing compile/missing_pronunciations.txt in $BASE_MODEL"
command -v rsync >/dev/null || die "rsync required"
command -v ssh   >/dev/null || die "ssh required"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$GPU_HOST" \
    'command -v docker >/dev/null && docker image inspect kaldi-opengrm:latest >/dev/null 2>&1' \
    || die "$GPU_HOST needs docker and the kaldi-opengrm:latest image (see tools/kaldi-opengrm.Dockerfile)"

WORK=$(mktemp -d -t vosk-vocab-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# ---- 1. Extract vocabulary ---------------------------------------------
log "=== 1. Extract vocabulary ==="
log "corpus: ${CORPUS[*]}"
"$SCRIPT_DIR/extract_vocabulary.py" \
    --model "$BASE_MODEL" \
    --output "$WORK" \
    --top 1000 \
    --min-occurrences 3 \
    "${CORPUS[@]}" >"$WORK/extract.log"
tail -n 20 "$WORK/extract.log"

[ -s "$WORK/extra.dic" ] || die "no vocabulary extracted — nothing to build"
mv "$WORK/extra_contexts.txt" "$WORK/extra.txt"

# ---- 2. Stage the remote work dir --------------------------------------
log "=== 2. Stage $GPU_HOST:$GPU_WORK_DIR/vosk-build/ ==="

ssh "$GPU_HOST" "mkdir -p $GPU_WORK_DIR/vosk-build/compile/db"

# Model inputs (am/, compile/db/, lgraph-base.lm.gz, missing_pronunciations.txt).
# The filter list keeps the rsync to exactly what compile-inner.sh reads.
rsync -az --delete \
    --include='am/' --include='am/**' \
    --include='compile/' \
    --include='compile/db/' --include='compile/db/**' \
    --include='compile/lgraph-base.lm.gz' \
    --include='compile/missing_pronunciations.txt' \
    --exclude='*' \
    "$BASE_MODEL/" \
    "$GPU_HOST:$GPU_WORK_DIR/vosk-build/"

# Compile scripts (canonical copies live in tools/).
rsync -az --chmod=F755 \
    "$SCRIPT_DIR/compile-lgraph-docker.sh" \
    "$SCRIPT_DIR/compile-inner.sh" \
    "$SCRIPT_DIR/dict-pruned.py" \
    "$GPU_HOST:$GPU_WORK_DIR/vosk-build/compile/"

# This build's vocabulary.
rsync -az \
    "$WORK/extra.txt" "$WORK/extra.dic" \
    "$GPU_HOST:$GPU_WORK_DIR/vosk-build/compile/db/"

# ---- 3. Build in the container on $GPU_HOST ---------------------------
log "=== 3. Build on $GPU_HOST ==="
ssh -t "$GPU_HOST" "cd $GPU_WORK_DIR/vosk-build/compile && ./compile-lgraph-docker.sh"

# ---- 4. Fetch graph and assemble the installed model ------------------
log "=== 4. Fetch graph and assemble locally ==="
OUT_NAME="vosk-model-en-us-0.22-lgraph-$DATE"
OUT="$MODELS_DIR/$OUT_NAME"
if [ -e "$OUT" ]; then
    warn "$OUT exists — removing before install"
    rm -rf "$OUT"
fi
mkdir -p "$OUT"

# am/, conf/, ivector/ come from the local base (unchanged across builds).
for d in am conf ivector; do
    cp -r "$BASE_MODEL/$d" "$OUT/"
done

# Fresh graph from the remote build.
rsync -az --delete \
    "$GPU_HOST:$GPU_WORK_DIR/vosk-build/graph/" \
    "$OUT/graph/"

[ -f "$OUT/graph/HCLr.fst" ] || die "build produced no HCLr.fst"
file "$OUT/graph/HCLr.fst" | grep -q "olabel_lookahead" \
    || warn "HCLr.fst is not olabel_lookahead — model will produce garbage"

# Sanity-check: sampled domain words must appear in the installed words.txt.
# awk (not head) does the truncation — `awk | head -20` trips SIGPIPE
# under set -o pipefail and aborts the script silently.
sample=$(awk 'NR<=20 {print $1}' "$WORK/extra.dic")
missing=0
for w in $sample; do
    grep -qE "^${w}( |$)" "$OUT/graph/words.txt" || missing=$((missing+1))
done
[ "$missing" -gt 15 ] \
    && die "only $((20-missing))/20 sampled domain words are in graph/words.txt — build likely used stale artifacts"
log "vocab check: $((20-missing))/20 sampled domain words present"

cat > "$OUT/manifest.json" <<EOF
{
  "base_model": "$(basename "$BASE_MODEL")",
  "build_date": "$(date -Iseconds)",
  "corpus": [$(printf '"%s",' "${CORPUS[@]}" | sed 's/,$//')],
  "gpu_host": "$GPU_HOST",
  "vocab_words": $(wc -l < "$OUT/graph/words.txt"),
  "domain_words": $(wc -l < "$WORK/extra.dic")
}
EOF

log "installed: $OUT ($(du -sh "$OUT" | cut -f1), $(wc -l < "$OUT/graph/words.txt") words)"

# ---- 5. Optionally switch talkie --------------------------------------
if [ $SWITCH -eq 1 ]; then
    log "=== 5. Switch talkie to $OUT_NAME ==="
    CONF=${XDG_CONFIG_HOME:+$XDG_CONFIG_HOME/talkie.conf}
    CONF=${CONF:-$HOME/.talkie.conf}
    if [ ! -f "$CONF" ]; then
        printf '{"vosk_modelfile":"%s"}\n' "$OUT_NAME" > "$CONF"
    elif command -v jq >/dev/null; then
        tmp=$(mktemp)
        jq --arg m "$OUT_NAME" '.vosk_modelfile = $m' "$CONF" > "$tmp" && mv "$tmp" "$CONF"
    else
        warn "jq not installed; edit $CONF manually to set vosk_modelfile=\"$OUT_NAME\""
    fi
    log "wrote $CONF (talkie will hot-swap on next filewatch tick)"
else
    log "to use the new model:"
    log "  jq --arg m $OUT_NAME '.vosk_modelfile = \$m' ~/.config/talkie.conf | sponge ~/.config/talkie.conf"
    log "  # or pass --switch next time"
fi

# ---- 6. Remote cleanup -------------------------------------------------
if [ $KEEP_REMOTE -eq 0 ]; then
    log "=== 6. Clean remote work dir ==="
    ssh "$GPU_HOST" "rm -rf $GPU_WORK_DIR/vosk-build"
else
    log "--keep-remote: leaving $GPU_HOST:$GPU_WORK_DIR/vosk-build/ in place"
fi
