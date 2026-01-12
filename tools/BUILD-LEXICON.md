# Talkie Lexicon Build Procedure

## Overview

The lexicon (`talkie.lex`) maps words to their parts of speech (POS) and phonemes.
This is used for homophone disambiguation in the speech recognition post-processor.

## Output Format

Tab-separated: `word<tab>POS<tab>phonemes`

```
their    D        dh eh r
there    vrN!     dh eh r
they're  r+V      dh eh r
```

## POS Codes (Moby-style)

| Code | Meaning |
|------|---------|
| N | Noun |
| V | Verb (participle) |
| t | Verb (transitive) |
| i | Verb (intransitive) |
| A | Adjective |
| v | Adverb |
| C | Conjunction |
| P | Preposition |
| ! | Interjection |
| r | Pronoun |
| D | Determiner |

## POS Source Prefixes

| Prefix | Source |
|--------|--------|
| (none) | Moby Part of Speech |
| $ | Wiktionary |
| ~ | Lemma lookup (inflected → base form) |
| ^ | WordNet |
| % | spaCy POS tagger |
| ' | Possessive (base word POS + apostrophe) |
| X | Unknown |

## Data Sources

### 1. Vocabulary (vosk-words.txt)
- **Origin**: `gpu:~/vosk-compile/data/lang/words.txt`
- **Built by**: Kaldi's `utils/prepare_lang.sh` during model compilation
- **Contains**: Words in both the pronunciation dictionary AND language model
- **Extraction**: `extract-vosk-vocab.py` filters special tokens (!SIL, [noise], etc.)

### 2. Moby Part of Speech (mobypos.txt)
- **Origin**: Project Gutenberg / archive.org
- **URL**: https://archive.org/download/mobypartofspeech03203gut/mobypos.txt
- **Coverage**: 228k words with detailed POS codes
- **Era**: 1990s - comprehensive but missing modern words

### 3. Wiktionary (wiktionary-pos.tsv)
- **Origin**: https://kaikki.org/dictionary/English/
- **Raw data**: `wiktionary-english.jsonl` (2.7GB)
- **Extraction**: `extract-wiktionary-pos.py` converts to Moby-style codes
- **Coverage**: 1.3M words including proper nouns and modern vocabulary

### 4. Pronunciations (en.dic + base_missing.dic)
- **en.dic**: From vosk-model-en-us-0.22-compile package
- **base_missing.dic**: Phonetisaurus-generated pronunciations for missing words

## Build Pipeline

```
┌─────────────────┐     ┌──────────────────┐
│ vosk-words.txt  │────▶│extract-vosk-vocab│────▶ vosk-vocab.txt
└─────────────────┘     └──────────────────┘      (312k words)

┌─────────────────┐     ┌──────────────────┐
│wiktionary.jsonl │────▶│extract-wiktionary│────▶ wiktionary-pos.tsv
│    (2.7GB)      │     │     -pos.py      │      (1.3M words, 18MB)
└─────────────────┘     └──────────────────┘

┌─────────────────┐
│  mobypos.txt    │────┐
│  (228k words)   │    │
└─────────────────┘    │
                       │     ┌──────────────────┐
┌─────────────────┐    ├────▶│ build-lexicon.py │────▶ talkie.lex
│wiktionary-pos   │────┤     └──────────────────┘
│    .tsv         │    │
└─────────────────┘    │
                       │
┌─────────────────┐    │
│ vosk-vocab.txt  │────┤
└─────────────────┘    │
                       │
┌─────────────────┐    │
│ en.dic +        │────┘
│ base_missing.dic│
└─────────────────┘
```

## POS Resolution Order

1. **Moby** - Direct lookup (most detailed POS codes)
2. **Wiktionary** - Direct lookup (broader coverage)
3. **Possessive base** - Strip `'s` and lookup base word
4. **Lemma → Moby** - spaCy lemmatization, then Moby lookup
5. **Lemma → Wiktionary** - spaCy lemmatization, then Wiktionary lookup
6. **WordNet** - NLTK WordNet synsets
7. **spaCy POS** - Universal POS tags converted to Moby-style
8. **Unknown (X)** - No source found

## Coverage Results (312k vocabulary)

| Source | Count | Coverage |
|--------|-------|----------|
| Moby | 85,679 | 27.4% |
| Wiktionary | 93,205 | 29.8% |
| Possessive base | 20,121 | 6.4% |
| Lemma (Moby) | 4,084 | 1.3% |
| Lemma (Wikt) | 1,169 | 0.4% |
| WordNet | 807 | 0.3% |
| spaCy | 104,717 | 33.5% |
| **Unknown** | **2,539** | **0.8%** |

## Scripts

| Script | Purpose |
|--------|---------|
| `rebuild-lexicon.sh` | Main build script |
| `build-lexicon.py` | Combines all sources into talkie.lex |
| `extract-vosk-vocab.py` | Extracts vocab from Kaldi words.txt |
| `extract-wiktionary-pos.py` | Extracts POS from Wiktionary dump |
| `extract-lm-vocab.py` | (Alternative) Extract vocab from ARPA LM |

## Requirements

```bash
# Python packages (in venv)
pip install spacy nltk
python -m spacy download en_core_web_sm
python -c "import nltk; nltk.download('wordnet')"
```

## Rebuilding

```bash
cd tools
source ../venv/bin/activate
./rebuild-lexicon.sh
```

## Unknown Words

The 0.8% unknowns are primarily:
- Partial/interrupted words: `wat-`, `cinema-`, `osteopor-`
- Archaic contractions: `perch'd`, `reveal'd`, `thron'd`
- Foreign names with diacritics: `potočnik`, `zastava`
- French phrases: `l'oeil`, `l'oyseleur`
