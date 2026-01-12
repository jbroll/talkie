#!/bin/bash
# Rebuild talkie.lex - the authoritative lexicon combining:
#   - Word list from Vosk model vocabulary
#   - POS tags from Moby Part-of-Speech (with contraction fixes)
#   - Pronunciations from en.dic + generated base_missing.dic
#
# Data sources:
#   mobypos.txt - Moby POS (download from Project Gutenberg if missing)
#   en.dic - From vosk-model-en-us-0.22-compile package
#   base_missing.dic - Generated pronunciations for words not in en.dic
#   words.txt - Model vocabulary

set -e
cd "$(dirname "$0")"

MOBY_POS="mobypos.txt"
WIKT_POS="wiktionary-pos.tsv"
EN_DIC="$HOME/Downloads/vosk-model-en-us-0.22-compile/db/en.dic"
BASE_MISSING="base_missing.dic"
OUTPUT="talkie.lex"

# Vocabulary source: Kaldi words.txt from model compilation
# Origin: gpu:~/vosk-compile/data/lang/words.txt
# Built by: utils/prepare_lang.sh from lexicon + language model
# Contains words that are in BOTH the pronunciation dictionary AND the LM
VOSK_WORDS="vosk-words.txt"
VOSK_VOCAB="vosk-vocab.txt"

# Check for Moby POS file
if [ ! -f "$MOBY_POS" ]; then
    echo "Downloading Moby POS from archive.org..."
    curl -sL "https://archive.org/download/mobypartofspeech03203gut/mobypos.txt" -o "$MOBY_POS"
fi

# Extract clean vocabulary from Kaldi words.txt (filter special tokens)
if [ ! -f "$VOSK_VOCAB" ] || [ "$VOSK_WORDS" -nt "$VOSK_VOCAB" ]; then
    echo "Extracting vocabulary from Vosk words.txt..."
    python3 extract-vosk-vocab.py "$VOSK_WORDS" "$VOSK_VOCAB"
fi

# Check dependencies
for f in "$MOBY_POS" "$WIKT_POS" "$EN_DIC" "$VOSK_VOCAB" "$BASE_MISSING"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Missing required file: $f" >&2
        exit 1
    fi
done

echo "Building lexicon..."
python3 build-lexicon.py \
    "$MOBY_POS" \
    "$WIKT_POS" \
    "$EN_DIC" \
    "$VOSK_VOCAB" \
    "$OUTPUT" \
    "$BASE_MISSING"

echo ""
echo "Done: $OUTPUT"
wc -l "$OUTPUT"
