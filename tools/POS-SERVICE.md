# POS Service Data Files

The POS disambiguation service uses data derived from the Vosk language model to correct homophone errors in speech recognition output.

## Data Files

All files are in the `tools/` directory:

### 1. talkie.lex (Lexicon)

**Purpose**: Maps words to their parts of speech (POS)

**Format**: Tab-separated: `word<TAB>POS<TAB>phonemes`
```
their    D        dh eh r
there    vrN!     dh eh r
they're  r+V      dh eh r
```

**Source**: Built by `rebuild-lexicon.sh` combining:
- Moby Part of Speech (`mobypos.txt`)
- Wiktionary POS (`wiktionary-pos.tsv`)
- spaCy/WordNet fallbacks for missing words

**Derivation**: See `BUILD-LEXICON.md` for full details

---

### 2. unigram_probs.txt (Word Frequencies)

**Purpose**: Word probability tiebreaker when bigrams are unavailable

**Format**: Tab-separated: `word<TAB>probability`
```
the     0.06534
to      0.02481
they're 0.00047
```

**Source**: Vosk RNNLM unigram probabilities

**Derivation**:
```bash
# On gpu host:
cd ~/vosk-compile/exp/rnnlm
paste words.txt unigram_probs.txt | awk -F'\t' 'NF==2 {print $1"\t"$2}'

# Copy to local:
scp gpu:~/vosk-compile/exp/rnnlm/joined_unigrams.txt tools/unigram_probs.txt
```

---

### 3. pos-bigrams.tsv (POS Transition Probabilities)

**Purpose**: Fallback when word bigrams are unavailable; captures P(POS2 | POS1)

**Format**: Tab-separated: `pos1<TAB>pos2<TAB>probability`
```
V       N       0.575928    # Noun after verb (57.6%)
V       P       0.077191    # Preposition after verb (7.7%)
r       V       0.175465    # Verb after pronoun (17.5%)
```

**Source**: Derived from ARPA language model word bigrams mapped to POS via lexicon

**Derivation**:
```bash
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 tools/extract-pos-bigrams.py tools/talkie.lex > tools/pos-bigrams.tsv
```

---

### 4. word-bigrams.tsv (Word Bigram Log Probabilities)

**Purpose**: Primary disambiguation signal; P(word | prev_word) and P(next_word | word)

**Format**: Tab-separated: `word1<TAB>word2<TAB>log10_probability`
```
they're going   -1.410277   # "they're going" very likely
there   going   -3.468647   # "there going" much less likely
their   going   -3.895985   # "their going" even less likely
```

**Source**: Word bigrams from ARPA language model, filtered to homophones

**Derivation**:
```bash
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 tools/extract-word-bigrams.py > tools/word-bigrams.tsv
```

**Size**: ~150k bigrams involving homophone words (filtered by log_prob > -2.0)

---

### 5. distinguishing-trigrams.tsv (High-Value Trigram Contexts)

**Purpose**: Trigram contexts where longer context picks a different homophone than bigrams alone

**Format**: Tab-separated: `prev<TAB>homophone<TAB>next<TAB>log_prob<TAB>bigram_pick<TAB>trigram_pick`
```
to      sea     again   -2.188984       see     sea
to      see     again   -3.271974       see     sea
a       see     saw     -1.286652       sea     see
a       sea     saw     -3.863681       sea     see
```

**Interpretation**:
- Row 1-2: In "to __ again", bigrams would pick "see", but trigrams correctly pick "sea"
- Row 3-4: In "a __ saw" (see-saw), bigrams would pick "sea", but trigrams correctly pick "see"

**Source**: Trigrams where trigram probability selects different homophone than bigram-only scoring

**Derivation**:
```bash
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 tools/extract-distinguishing-trigrams.py tools/word-bigrams.tsv > tools/distinguishing-trigrams.tsv
```

**Size**: ~133k entries covering ~55k unique (prev, next) contexts

---

## Data Flow

```
ARPA Language Model (en-230k-0.5.lm.gz)
├── word trigrams ────────────────────> distinguishing-trigrams.tsv (HIGHEST PRIORITY)
│   filtered where trigram != bigram decision
│
├── word bigrams ──────────────────────> word-bigrams.tsv (PRIMARY)
│   filtered to homophone words, log_prob > -2.0
│
├── word bigrams + lexicon POS ────────> pos-bigrams.tsv (FALLBACK)
│   mapped words → POS, counted transitions
│
└── (via RNNLM training)
    unigram_probs.txt ─────────────────> unigram_probs.txt (TIEBREAKER)


Moby + Wiktionary + spaCy ─────────────> talkie.lex (POS LOOKUP)
```

## Scoring Algorithm

For each homophone candidate, in priority order:

1. **Distinguishing trigrams** (if exact (prev, next) context matches):
   Use trigram log probability directly - these are high-value corrections

2. **Word bigrams** (if available):
   `score = log P(word|prev) + log P(next|word)`

3. **POS bigrams** (fallback):
   `score = log P(POS|prev_POS) * P(next_POS|POS) + log P_unigram(word)`

The candidate with the highest score is selected. On ties, the original word is kept.

## Logging

All disambiguation decisions are logged to `logs/homophone_decisions.jsonl`:
```json
{
  "timestamp": "2026-01-12T12:18:45.657510",
  "text": "they're going home",
  "word_idx": 0,
  "original": "they're",
  "prev_word": null,
  "next_word": "going",
  "scores": {"there": -6.47, "their": -6.90, "they're": -4.41},
  "chosen": "they're",
  "changed": false
}
```

## Rebuilding Data Files

```bash
cd tools

# Rebuild lexicon
./rebuild-lexicon.sh

# Rebuild POS bigrams (requires ssh to gpu)
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 extract-pos-bigrams.py talkie.lex > pos-bigrams.tsv

# Rebuild word bigrams (requires ssh to gpu)
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 extract-word-bigrams.py > word-bigrams.tsv

# Rebuild distinguishing trigrams (requires word bigrams first)
ssh gpu "zcat ~/vosk-compile/db/en-230k-0.5.lm.gz" | \
    python3 extract-distinguishing-trigrams.py word-bigrams.tsv > distinguishing-trigrams.tsv
```

## GPU Host Paths

The source data lives on the gpu host:
- ARPA LM: `gpu:~/vosk-compile/db/en-230k-0.5.lm.gz`
- RNNLM unigrams: `gpu:~/vosk-compile/exp/rnnlm/unigram_probs.txt`
- Words list: `gpu:~/vosk-compile/data/lang/words.txt`
