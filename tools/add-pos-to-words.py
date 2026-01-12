#!/usr/bin/env python3
"""
Add part-of-speech tags from Moby lexicon to our word list.

Input: vocabulary words.txt (from Vosk model)
Output: words with POS tags, and list of words not in Moby

Moby POS codes:
  N = Noun
  V = Verb (participle)
  t = Verb (transitive)
  i = Verb (intransitive)
  A = Adjective
  v = Adverb
  C = Conjunction
  P = Preposition
  ! = Interjection
  r = Pronoun
  D = Determiner
  h = Noun Phrase
  I = Indefinite Article
  o = Nominative
"""

import sys


def load_moby_pos(moby_path: str) -> dict[str, str]:
    """Load Moby POS file into word -> POS codes dict."""
    pos_map = {}
    with open(moby_path, 'r', encoding='latin-1') as f:
        for line in f:
            line = line.strip()
            if '\\' not in line:
                continue
            # Format: word\POS_CODES
            parts = line.rsplit('\\', 1)
            if len(parts) == 2:
                word, pos = parts
                pos_map[word.lower()] = pos
    return pos_map


# Contraction patterns - Moby often misclassifies these
CONTRACTION_POS = {
    # 're contractions = pronoun + are (verb)
    "they're": "r+V",   # pronoun + verb
    "you're": "r+V",
    "we're": "r+V",
    "who're": "r+V",

    # 's contractions = noun/pronoun + is/has OR possessive
    # These are ambiguous - could be "it is" or possessive "it's"
    "it's": "r+V",      # pronoun + verb (it is/has)
    "he's": "r+V",
    "she's": "r+V",
    "who's": "r+V",
    "what's": "r+V",
    "that's": "r+V",
    "there's": "v+V",   # adverb + verb (there is)
    "here's": "v+V",
    "where's": "v+V",
    "how's": "v+V",
    "let's": "V+r",     # verb + pronoun (let us)

    # 've contractions = pronoun + have
    "i've": "r+V",
    "you've": "r+V",
    "we've": "r+V",
    "they've": "r+V",
    "who've": "r+V",

    # 'll contractions = pronoun + will
    "i'll": "r+V",
    "you'll": "r+V",
    "he'll": "r+V",
    "she'll": "r+V",
    "we'll": "r+V",
    "they'll": "r+V",
    "it'll": "r+V",
    "that'll": "r+V",
    "who'll": "r+V",

    # 'd contractions = pronoun + would/had
    "i'd": "r+V",
    "you'd": "r+V",
    "he'd": "r+V",
    "she'd": "r+V",
    "we'd": "r+V",
    "they'd": "r+V",
    "it'd": "r+V",
    "who'd": "r+V",

    # n't contractions = verb + not
    "isn't": "V+v",
    "aren't": "V+v",
    "wasn't": "V+v",
    "weren't": "V+v",
    "don't": "V+v",
    "doesn't": "V+v",
    "didn't": "V+v",
    "haven't": "V+v",
    "hasn't": "V+v",
    "hadn't": "V+v",
    "won't": "V+v",
    "wouldn't": "V+v",
    "can't": "V+v",
    "couldn't": "V+v",
    "shouldn't": "V+v",
    "mustn't": "V+v",
    "needn't": "V+v",
    "mightn't": "V+v",
    "shan't": "V+v",

    # Informal contractions
    "gonna": "V",       # going to -> verb
    "wanna": "V",       # want to -> verb
    "gotta": "V",       # got to -> verb
    "kinda": "v",       # kind of -> adverb
    "sorta": "v",       # sort of -> adverb
    "coulda": "V",      # could have -> verb
    "shoulda": "V",
    "woulda": "V",
    "musta": "V",       # must have -> verb
    "oughta": "V",      # ought to -> verb
    "lemme": "V+r",     # let me -> verb + pronoun
    "gimme": "V+r",     # give me -> verb + pronoun
    "dunno": "V",       # don't know -> verb
}


def apply_contraction_fixes(pos_map: dict[str, str]) -> dict[str, str]:
    """Override Moby POS for contractions with correct classifications."""
    for word, pos in CONTRACTION_POS.items():
        pos_map[word] = pos
    return pos_map


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


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <moby_pos.txt> <words.txt> [output.txt]", file=sys.stderr)
        print(f"  moby_pos.txt: Moby Part of Speech file", file=sys.stderr)
        print(f"  words.txt: Vosk vocabulary file", file=sys.stderr)
        print(f"  output.txt: Output file (default: stdout)", file=sys.stderr)
        sys.exit(1)

    moby_path = sys.argv[1]
    vocab_path = sys.argv[2]
    output_path = sys.argv[3] if len(sys.argv) > 3 else None

    print(f"Loading Moby POS from {moby_path}...", file=sys.stderr)
    moby_pos = load_moby_pos(moby_path)
    print(f"  Loaded {len(moby_pos)} words", file=sys.stderr)

    print(f"Applying contraction fixes...", file=sys.stderr)
    moby_pos = apply_contraction_fixes(moby_pos)
    print(f"  Fixed {len(CONTRACTION_POS)} contractions", file=sys.stderr)

    print(f"Loading vocabulary from {vocab_path}...", file=sys.stderr)
    vocab = load_vocabulary(vocab_path)
    print(f"  Loaded {len(vocab)} words", file=sys.stderr)

    # Match words
    matched = {}
    missing = set()

    for word in vocab:
        if word in moby_pos:
            matched[word] = moby_pos[word]
        else:
            missing.add(word)

    # Stats
    print(f"\nResults:", file=sys.stderr)
    print(f"  Matched: {len(matched)} ({100*len(matched)/len(vocab):.1f}%)", file=sys.stderr)
    print(f"  Missing: {len(missing)} ({100*len(missing)/len(vocab):.1f}%)", file=sys.stderr)

    # Analyze missing words
    missing_categories = {
        'proper_nouns': [],  # Capitalized names
        'contractions': [],  # Words with apostrophes
        'hyphenated': [],    # Hyphenated compounds
        'numbers': [],       # Numeric
        'other': []
    }

    for word in sorted(missing):
        if any(c.isdigit() for c in word):
            missing_categories['numbers'].append(word)
        elif "'" in word:
            missing_categories['contractions'].append(word)
        elif "-" in word:
            missing_categories['hyphenated'].append(word)
        elif word[0].isupper() if word else False:
            missing_categories['proper_nouns'].append(word)
        else:
            missing_categories['other'].append(word)

    print(f"\nMissing word breakdown:", file=sys.stderr)
    for cat, words in missing_categories.items():
        print(f"  {cat}: {len(words)}", file=sys.stderr)
        if len(words) <= 10:
            for w in words:
                print(f"    {w}", file=sys.stderr)
        else:
            for w in words[:5]:
                print(f"    {w}", file=sys.stderr)
            print(f"    ... and {len(words)-5} more", file=sys.stderr)

    # Output matched words with POS
    out = open(output_path, 'w') if output_path else sys.stdout
    for word in sorted(matched.keys()):
        out.write(f"{word}\t{matched[word]}\n")

    if output_path:
        out.close()
        print(f"\nWrote {len(matched)} entries to {output_path}", file=sys.stderr)

    # Write missing words to separate file
    if output_path:
        missing_path = output_path.replace('.txt', '-missing.txt')
        with open(missing_path, 'w') as f:
            for word in sorted(missing):
                f.write(f"{word}\n")
        print(f"Wrote {len(missing)} missing words to {missing_path}", file=sys.stderr)


if __name__ == '__main__':
    main()
