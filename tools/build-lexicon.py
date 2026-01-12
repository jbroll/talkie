#!/usr/bin/env python3
"""
Build unified lexicon file combining:
  - Word
  - Part of speech (Moby codes, or X for unknown)
  - Phonemes (from pronunciation dictionary)

Output format (tab-separated):
  word    POS    phoneme1 phoneme2 phoneme3 ...

Example:
  their    D      dh eh r
  there    vrN!   dh eh r
  they're  r+V    dh eh r

POS codes from Moby:
  N = Noun, V = Verb (participle), t = Verb (transitive), i = Verb (intransitive)
  A = Adjective, v = Adverb, C = Conjunction, P = Preposition
  ! = Interjection, r = Pronoun, D = Determiner, h = Noun Phrase
  X = Unknown (not in any source)
  ~X = POS inherited from lemma (e.g., ~V means lemma is a verb)
  ^X = POS from WordNet (e.g., ^N means WordNet says noun)
  %X = POS from spaCy (e.g., %V means spaCy says verb)

Compound codes for contractions:
  r+V = pronoun + verb (they're, you're, I'll, etc.)
  V+v = verb + adverb/not (don't, won't, can't, etc.)

Requires: spacy with en_core_web_sm model
  pip install spacy
  python -m spacy download en_core_web_sm
"""

import sys
import re
import spacy
from nltk.corpus import wordnet as wn


# Contraction POS overrides - Moby misclassifies these
CONTRACTION_POS = {
    # 're contractions = pronoun + are
    "they're": "r+V", "you're": "r+V", "we're": "r+V", "who're": "r+V",

    # 's contractions = pronoun + is/has
    "it's": "r+V", "he's": "r+V", "she's": "r+V", "who's": "r+V",
    "what's": "r+V", "that's": "r+V", "there's": "v+V", "here's": "v+V",
    "where's": "v+V", "how's": "v+V", "let's": "V+r",

    # 've contractions = pronoun + have
    "i've": "r+V", "you've": "r+V", "we've": "r+V", "they've": "r+V", "who've": "r+V",

    # 'll contractions = pronoun + will
    "i'll": "r+V", "you'll": "r+V", "he'll": "r+V", "she'll": "r+V",
    "we'll": "r+V", "they'll": "r+V", "it'll": "r+V", "that'll": "r+V", "who'll": "r+V",

    # 'd contractions = pronoun + would/had
    "i'd": "r+V", "you'd": "r+V", "he'd": "r+V", "she'd": "r+V",
    "we'd": "r+V", "they'd": "r+V", "it'd": "r+V", "who'd": "r+V",

    # n't contractions = verb + not
    "isn't": "V+v", "aren't": "V+v", "wasn't": "V+v", "weren't": "V+v",
    "don't": "V+v", "doesn't": "V+v", "didn't": "V+v",
    "haven't": "V+v", "hasn't": "V+v", "hadn't": "V+v",
    "won't": "V+v", "wouldn't": "V+v", "can't": "V+v", "couldn't": "V+v",
    "shouldn't": "V+v", "mustn't": "V+v", "needn't": "V+v", "mightn't": "V+v", "shan't": "V+v",

    # Informal
    "gonna": "V", "wanna": "V", "gotta": "V", "kinda": "v", "sorta": "v",
    "coulda": "V", "shoulda": "V", "woulda": "V", "musta": "V", "oughta": "V",
    "lemme": "V+r", "gimme": "V+r", "dunno": "V",
}


def load_moby_pos(moby_path: str) -> dict[str, str]:
    """Load Moby POS file."""
    pos_map = {}
    with open(moby_path, 'r', encoding='latin-1') as f:
        for line in f:
            line = line.strip()
            if '\\' not in line:
                continue
            parts = line.rsplit('\\', 1)
            if len(parts) == 2:
                word, pos = parts
                pos_map[word.lower()] = pos

    # Apply contraction fixes
    for word, pos in CONTRACTION_POS.items():
        pos_map[word] = pos

    return pos_map


def load_pronunciations(dic_path: str) -> dict[str, list[str]]:
    """Load pronunciation dictionary. Returns word -> list of phoneme strings."""
    pronunciations = {}
    with open(dic_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            word = parts[0].lower()
            phonemes = ' '.join(parts[1:])

            # Handle pronunciation variants like "read(2)"
            base_word = re.sub(r'\(\d+\)$', '', word)

            if base_word not in pronunciations:
                pronunciations[base_word] = []
            pronunciations[base_word].append(phonemes)

    return pronunciations


def load_vocabulary(vocab_path: str) -> set[str]:
    """Load vocabulary words from Vosk words.txt."""
    words = set()
    with open(vocab_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if parts:
                word = parts[0]
                # Skip special tokens
                if not word.startswith('<') and not word.startswith('#'):
                    words.add(word.lower())
    return words


def load_wiktionary_pos(wikt_path: str) -> dict[str, str]:
    """Load Wiktionary POS from pre-extracted TSV file.

    File format: word<tab>POS (where POS is Moby-style codes like NV, A, etc.)
    """
    pos_map = {}
    with open(wikt_path, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                word, pos = parts
                pos_map[word.lower()] = pos
    return pos_map


def build_lemma_map(words: set[str], nlp) -> dict[str, str]:
    """Build word -> lemma mapping using spaCy.

    Process words in batches for efficiency.
    """
    lemmas = {}
    word_list = sorted(words)
    batch_size = 1000

    for i in range(0, len(word_list), batch_size):
        batch = word_list[i:i + batch_size]
        # Process each word as a single-token document
        for word in batch:
            doc = nlp(word)
            if doc and len(doc) > 0:
                lemmas[word] = doc[0].lemma_.lower()

        if (i + batch_size) % 10000 == 0:
            print(f"  Lemmatized {i + batch_size}/{len(word_list)}...", file=sys.stderr)

    return lemmas


def build_spacy_pos_map(words: set[str], nlp) -> dict[str, str]:
    """Build word -> POS mapping using spaCy's POS tagger.

    Returns Moby-style POS codes.
    """
    pos_map = {}
    word_list = sorted(words)
    batch_size = 1000

    for i in range(0, len(word_list), batch_size):
        batch = word_list[i:i + batch_size]
        for word in batch:
            doc = nlp(word)
            if doc and len(doc) > 0:
                spacy_pos = doc[0].pos_
                moby_pos = SPACY_TO_MOBY.get(spacy_pos)
                if moby_pos:
                    pos_map[word] = moby_pos

        if (i + batch_size) % 10000 == 0:
            print(f"  POS tagged {i + batch_size}/{len(word_list)}...", file=sys.stderr)

    return pos_map


# WordNet POS to Moby POS mapping
WORDNET_TO_MOBY = {
    'n': 'N',   # noun
    'v': 'V',   # verb
    'a': 'A',   # adjective
    's': 'A',   # adjective satellite (treat as adjective)
    'r': 'v',   # adverb (Moby uses lowercase v for adverb)
}

# spaCy Universal POS to Moby POS mapping
SPACY_TO_MOBY = {
    'NOUN': 'N',    # noun
    'PROPN': 'N',   # proper noun (still a noun syntactically)
    'VERB': 'V',    # verb
    'AUX': 'V',     # auxiliary verb
    'ADJ': 'A',     # adjective
    'ADV': 'v',     # adverb
    'ADP': 'P',     # adposition (preposition)
    'CCONJ': 'C',   # coordinating conjunction
    'SCONJ': 'C',   # subordinating conjunction
    'DET': 'D',     # determiner
    'PRON': 'r',    # pronoun
    'INTJ': '!',    # interjection
    # Skip: NUM, PART, PUNCT, SYM, X
}


def get_wordnet_pos(word: str) -> str | None:
    """Get POS from WordNet. Returns Moby-style code or None."""
    synsets = wn.synsets(word)
    if not synsets:
        return None

    # Collect all POS tags from synsets
    pos_tags = set()
    for syn in synsets:
        pos = WORDNET_TO_MOBY.get(syn.pos())
        if pos:
            pos_tags.add(pos)

    if not pos_tags:
        return None

    # Return combined POS (e.g., "NV" for noun+verb)
    return ''.join(sorted(pos_tags))


def get_pos_with_lemma(word: str, moby_pos: dict, wiktionary_pos: dict, lemmas: dict, spacy_pos: dict) -> tuple[str, str]:
    """Get POS from multiple sources with fallback chain.

    Order: Moby → Wiktionary → possessive base → lemma lookup → WordNet → spaCy → unknown
    Returns (pos, source) where source indicates the data source.
    """
    # Direct lookup in Moby (most detailed POS codes)
    if word in moby_pos:
        return moby_pos[word], 'moby'

    # Try Wiktionary (large coverage, good for proper nouns)
    if word in wiktionary_pos:
        return '$' + wiktionary_pos[word], 'wiktionary'

    # Handle possessives (word's) - look up base word
    if word.endswith("'s") and len(word) > 2:
        base = word[:-2]
        if base in moby_pos:
            return moby_pos[base] + "'", 'possessive'
        if base in wiktionary_pos:
            return '$' + wiktionary_pos[base] + "'", 'possessive'

    # Try lemma lookup in Moby
    lemma = lemmas.get(word)
    if lemma and lemma != word and lemma in moby_pos:
        return '~' + moby_pos[lemma], 'lemma'

    # Try lemma lookup in Wiktionary
    if lemma and lemma != word and lemma in wiktionary_pos:
        return '$~' + wiktionary_pos[lemma], 'wikt_lemma'

    # Try WordNet
    wn_pos = get_wordnet_pos(word)
    if wn_pos:
        return '^' + wn_pos, 'wordnet'

    # Try WordNet with lemma
    if lemma and lemma != word:
        wn_pos = get_wordnet_pos(lemma)
        if wn_pos:
            return '^' + wn_pos, 'wordnet'

    # Try spaCy POS tagger
    if word in spacy_pos:
        return '%' + spacy_pos[word], 'spacy'

    return 'X', 'unknown'


def main():
    if len(sys.argv) < 6:
        print(f"Usage: {sys.argv[0]} <moby_pos.txt> <wiktionary_pos.tsv> <en.dic> <words.txt> <output.lex> [extra.dic ...]", file=sys.stderr)
        print(f"", file=sys.stderr)
        print(f"  moby_pos.txt: Moby Part of Speech file", file=sys.stderr)
        print(f"  wiktionary_pos.tsv: Wiktionary POS file (from extract-wiktionary-pos.py)", file=sys.stderr)
        print(f"  en.dic: Primary pronunciation dictionary", file=sys.stderr)
        print(f"  words.txt: Model vocabulary file (only these words will be included)", file=sys.stderr)
        print(f"  output.lex: Output lexicon file", file=sys.stderr)
        print(f"  extra.dic: Additional pronunciation dictionaries (e.g., base_missing.dic)", file=sys.stderr)
        sys.exit(1)

    moby_path = sys.argv[1]
    wikt_path = sys.argv[2]
    dic_path = sys.argv[3]
    vocab_path = sys.argv[4]
    output_path = sys.argv[5]
    extra_dics = sys.argv[6:] if len(sys.argv) > 6 else []

    print(f"Loading Moby POS from {moby_path}...", file=sys.stderr)
    moby_pos = load_moby_pos(moby_path)
    print(f"  Loaded {len(moby_pos)} words", file=sys.stderr)

    print(f"Loading Wiktionary POS from {wikt_path}...", file=sys.stderr)
    wiktionary_pos = load_wiktionary_pos(wikt_path)
    print(f"  Loaded {len(wiktionary_pos)} words", file=sys.stderr)

    print(f"Loading pronunciations from {dic_path}...", file=sys.stderr)
    pronunciations = load_pronunciations(dic_path)
    print(f"  Loaded {len(pronunciations)} words", file=sys.stderr)

    # Load additional pronunciation dictionaries
    for extra_dic in extra_dics:
        print(f"Loading extra pronunciations from {extra_dic}...", file=sys.stderr)
        extra_prons = load_pronunciations(extra_dic)
        # Merge - don't overwrite existing pronunciations
        added = 0
        for word, prons in extra_prons.items():
            if word not in pronunciations:
                pronunciations[word] = prons
                added += 1
        print(f"  Added {added} new words", file=sys.stderr)

    print(f"Loading vocabulary from {vocab_path}...", file=sys.stderr)
    vocabulary = load_vocabulary(vocab_path)
    print(f"  Loaded {len(vocabulary)} words", file=sys.stderr)

    # Find words not in Moby or Wiktionary that need spaCy processing
    # Also exclude possessives whose base word is in a dictionary
    def needs_spacy(word):
        if word in moby_pos or word in wiktionary_pos:
            return False
        # Check possessive base
        if word.endswith("'s") and len(word) > 2:
            base = word[:-2]
            if base in moby_pos or base in wiktionary_pos:
                return False
        return True

    unknown_words = {w for w in vocabulary if needs_spacy(w)}
    print(f"  Words needing spaCy: {len(unknown_words)}", file=sys.stderr)

    # Load spaCy and build lemma map
    print(f"Loading spaCy model...", file=sys.stderr)
    nlp = spacy.load("en_core_web_sm")
    print(f"Building lemma map for {len(unknown_words)} words...", file=sys.stderr)
    lemmas = build_lemma_map(unknown_words, nlp)

    # Build spaCy POS map for truly unknown words
    print(f"Building spaCy POS map for {len(unknown_words)} words...", file=sys.stderr)
    spacy_pos = build_spacy_pos_map(unknown_words, nlp)

    # Build lexicon from vocabulary (only words the model can output)
    print(f"Building lexicon...", file=sys.stderr)

    stats = {'moby': 0, 'wiktionary': 0, 'possessive': 0, 'lemma': 0, 'wikt_lemma': 0, 'wordnet': 0, 'spacy': 0, 'unknown': 0, 'no_pronunciation': 0}

    with open(output_path, 'w') as out:
        # Write header comment
        out.write("# Talkie Lexicon\n")
        out.write("# Format: word<tab>POS<tab>phonemes\n")
        out.write("# POS codes: N=Noun V=Verb A=Adj v=Adv P=Prep C=Conj r=Pron D=Det !=Interj\n")
        out.write("# Prefixes: ~=from lemma, $=from Wiktionary, ^=from WordNet, %=from spaCy, X=unknown\n")
        out.write("#\n")

        for word in sorted(vocabulary):
            # Get POS from multiple sources with fallback chain
            pos, source = get_pos_with_lemma(word, moby_pos, wiktionary_pos, lemmas, spacy_pos)
            stats[source] += 1

            # Get pronunciations (may have multiple, or none)
            if word in pronunciations:
                for phonemes in pronunciations[word]:
                    out.write(f"{word}\t{pos}\t{phonemes}\n")
            else:
                # Word in vocabulary but not in pronunciation dictionary
                out.write(f"{word}\t{pos}\t\n")
                stats['no_pronunciation'] += 1

    print(f"\nResults:", file=sys.stderr)
    print(f"  From Moby: {stats['moby']} ({100*stats['moby']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  From Wiktionary: {stats['wiktionary']} ({100*stats['wiktionary']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  From possessive base: {stats['possessive']} ({100*stats['possessive']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  From lemma (Moby): {stats['lemma']} ({100*stats['lemma']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  From lemma (Wikt): {stats['wikt_lemma']} ({100*stats['wikt_lemma']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  From WordNet: {stats['wordnet']} ({100*stats['wordnet']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  From spaCy: {stats['spacy']} ({100*stats['spacy']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  Unknown (X): {stats['unknown']} ({100*stats['unknown']/len(vocabulary):.1f}%)", file=sys.stderr)
    print(f"  No pronunciation: {stats['no_pronunciation']}", file=sys.stderr)
    print(f"\nWrote {output_path}", file=sys.stderr)


if __name__ == '__main__':
    main()
