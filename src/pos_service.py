#!/usr/bin/env python3
"""POS-based homophone disambiguation service.

Reads utterances from stdin, writes disambiguated text to stdout.
Runs as a persistent service to avoid process spawn overhead.

Architecture:
1. Load lexicon with pre-computed POS for each word
2. Build homophone index from pronunciation dictionary
3. For each utterance:
   - Use spaCy to determine expected POS in context
   - Look up possible POS for each homophone from lexicon
   - Select homophone whose POS matches expected

Protocol:
  - Input: one utterance per line on stdin
  - Output: disambiguated utterance on stdout
  - Stderr: debug/timing info
  - Empty line or EOF: exit

Usage:
  echo "I went to there house" | python3 pos_service.py

  # Or as persistent service:
  python3 pos_service.py &
  echo "I went to there house" > /proc/$!/fd/0
"""

import sys
import time
from pathlib import Path
from collections import defaultdict

# Try to load spaCy
try:
    import spacy
    nlp = spacy.load("en_core_web_sm")
    HAS_SPACY = True
except (ImportError, OSError):
    nlp = None
    HAS_SPACY = False


# Map spaCy Universal POS to simplified categories for matching
SPACY_POS_MAP = {
    'NOUN': 'N',
    'PROPN': 'N',
    'VERB': 'V',
    'AUX': 'V',
    'ADJ': 'A',
    'ADV': 'v',
    'ADP': 'P',
    'DET': 'D',
    'PRON': 'r',
    'CCONJ': 'C',
    'SCONJ': 'C',
    'INTJ': '!',
    'NUM': 'N',
}


class LexiconPOSService:
    # Curated homophone groups for disambiguation - only these will be considered
    # Each group contains words that are commonly confused in speech recognition
    HOMOPHONE_GROUPS = [
        {'their', 'there', "they're"},
        {'to', 'too', 'two'},
        {'your', "you're"},
        {'its', "it's"},
        {'know', 'no'},
        {'hear', 'here'},
        {'write', 'right'},
        {'whose', "who's"},
        {'were', 'where', "we're"},
        {'then', 'than'},
        {'affect', 'effect'},
        {'accept', 'except'},
        {'brake', 'break'},
        {'peace', 'piece'},
        {'weather', 'whether'},
        {'by', 'buy', 'bye'},
        {'wait', 'weight'},
        {'new', 'knew'},
        {'scene', 'seen'},
        {'threw', 'through'},
        {'whole', 'hole'},
        {'meat', 'meet'},
        {'would', 'wood'},
        {'one', 'won'},
        {'our', 'hour'},
        {'for', 'four'},
        {'be', 'bee'},
        {'sea', 'see'},
        {'bare', 'bear'},
        {'fair', 'fare'},
        {'pair', 'pear'},
        {'rain', 'reign'},
        {'tail', 'tale'},
        {'waist', 'waste'},
        {'weak', 'week'},
        {'which', 'witch'},
    ]

    def __init__(self, lexicon_path: str, unigram_path: str = None, bigram_path: str = None, word_bigram_path: str = None):
        self.word_pos = {}  # word -> set of possible POS chars
        self.homophones = {}  # word -> set of homophones (curated only)
        self.unigram_prob = {}  # word -> probability
        self.pos_bigrams = {}  # (pos1, pos2) -> probability
        self.word_bigrams = {}  # (word1, word2) -> log_probability

        self.load_lexicon(lexicon_path)
        self.build_homophones()
        if unigram_path:
            self.load_unigrams(unigram_path)
        if bigram_path:
            self.load_pos_bigrams(bigram_path)
        if word_bigram_path:
            self.load_word_bigrams(word_bigram_path)

    def load_lexicon(self, path: str):
        """Load word -> POS mapping from talkie.lex."""
        t0 = time.perf_counter()

        with open(path, 'r') as f:
            for line in f:
                if line.startswith('#'):
                    continue
                parts = line.strip().split('\t')
                if len(parts) >= 2:
                    word = parts[0].lower()
                    pos_raw = parts[1]

                    # Strip source prefixes ($, ~, ^, %) to get base POS
                    pos = pos_raw.lstrip('$~^%')

                    # Extract individual POS characters
                    # Handle compound like "r+V" -> {'r', 'V'}
                    pos_chars = set()
                    for p in pos.replace('+', ''):
                        if p in 'NVtiAvCPr!Dh':
                            pos_chars.add(p)

                    if pos_chars:
                        if word not in self.word_pos:
                            self.word_pos[word] = set()
                        self.word_pos[word].update(pos_chars)

        elapsed = (time.perf_counter() - t0) * 1000
        print(f"POS: loaded {len(self.word_pos)} words from lexicon ({elapsed:.0f}ms)", file=sys.stderr)

    def build_homophones(self):
        """Build homophone index from curated list."""
        # Use curated homophone groups only
        for group in self.HOMOPHONE_GROUPS:
            for word in group:
                self.homophones[word] = group

        print(f"POS: {len(self.HOMOPHONE_GROUPS)} curated homophone groups", file=sys.stderr)

    def load_unigrams(self, path: str):
        """Load unigram probabilities from file."""
        t0 = time.perf_counter()

        with open(path, 'r') as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) == 2:
                    word = parts[0].lower()
                    try:
                        prob = float(parts[1])
                        self.unigram_prob[word] = prob
                    except ValueError:
                        pass

        elapsed = (time.perf_counter() - t0) * 1000
        print(f"POS: loaded {len(self.unigram_prob)} unigram probs ({elapsed:.0f}ms)", file=sys.stderr)

    def load_pos_bigrams(self, path: str):
        """Load POS bigram transition probabilities from file."""
        t0 = time.perf_counter()

        with open(path, 'r') as f:
            for line in f:
                if line.startswith('#'):
                    continue
                parts = line.strip().split('\t')
                if len(parts) == 3:
                    pos1, pos2 = parts[0], parts[1]
                    try:
                        prob = float(parts[2])
                        self.pos_bigrams[(pos1, pos2)] = prob
                    except ValueError:
                        pass

        elapsed = (time.perf_counter() - t0) * 1000
        print(f"POS: loaded {len(self.pos_bigrams)} POS bigrams ({elapsed:.0f}ms)", file=sys.stderr)

    def load_word_bigrams(self, path: str):
        """Load word bigram log probabilities from file."""
        t0 = time.perf_counter()

        with open(path, 'r') as f:
            for line in f:
                if line.startswith('#'):
                    continue
                parts = line.strip().split('\t')
                if len(parts) == 3:
                    w1, w2 = parts[0], parts[1]
                    try:
                        log_prob = float(parts[2])
                        self.word_bigrams[(w1, w2)] = log_prob
                    except ValueError:
                        pass

        elapsed = (time.perf_counter() - t0) * 1000
        print(f"POS: loaded {len(self.word_bigrams)} word bigrams ({elapsed:.0f}ms)", file=sys.stderr)

    def get_neighbor_pos(self, words: list[str], word_index: int) -> tuple[str | None, str | None]:
        """Get POS of neighboring words (not the target word itself).

        Returns:
            (prev_pos, next_pos) - POS of words before and after the target
        """
        if not HAS_SPACY:
            return None, None

        # Analyze the utterance
        text = ' '.join(words)
        doc = nlp(text)

        # Build word index to token mapping
        tokens = list(doc)
        word_to_token = {}
        token_idx = 0
        char_pos = 0
        for w_idx, word in enumerate(words):
            while token_idx < len(tokens) and tokens[token_idx].idx < char_pos:
                token_idx += 1
            if token_idx < len(tokens):
                word_to_token[w_idx] = tokens[token_idx]
            char_pos += len(word) + 1

        prev_pos = None
        next_pos = None

        # Get previous word's POS
        if word_index > 0 and (word_index - 1) in word_to_token:
            token = word_to_token[word_index - 1]
            prev_pos = SPACY_POS_MAP.get(token.pos_)

        # Get next word's POS
        if word_index < len(words) - 1 and (word_index + 1) in word_to_token:
            token = word_to_token[word_index + 1]
            next_pos = SPACY_POS_MAP.get(token.pos_)

        return prev_pos, next_pos

    def pos_matches(self, word: str, expected_pos: str | None) -> bool:
        """Check if word can have the expected POS."""
        if expected_pos is None:
            return True

        possible = self.word_pos.get(word.lower(), set())

        # Map expected to possible matches
        # V matches V, t, i (all verb types)
        if expected_pos == 'V':
            return bool(possible & {'V', 't', 'i'})

        return expected_pos in possible

    def score_candidate(self, word: str, prev_pos: str | None, next_pos: str | None, prev_word: str | None, next_word: str | None) -> float:
        """Score how well a word fits using word bigrams (primary) or POS bigrams (fallback).

        Word bigrams P(word | prev_word) and P(next_word | word) capture specific
        contextual patterns much better than POS-level bigrams.
        """
        import math

        word_lower = word.lower()
        score = 0.0

        # Primary: Use word bigrams if available
        if self.word_bigrams:
            # P(word | prev_word)
            if prev_word:
                prev_lower = prev_word.lower()
                log_p_given_prev = self.word_bigrams.get((prev_lower, word_lower), -6.0)
            else:
                log_p_given_prev = -3.0  # Neutral at sentence start

            # P(next_word | word)
            if next_word:
                next_lower = next_word.lower()
                log_p_next_given = self.word_bigrams.get((word_lower, next_lower), -6.0)
            else:
                log_p_next_given = -3.0  # Neutral at sentence end

            score = log_p_given_prev + log_p_next_given
            return score

        # Fallback: POS bigrams + unigrams (if no word bigrams)
        word_pos_set = self.word_pos.get(word_lower, set())

        if not word_pos_set:
            return self._unigram_score(word_lower)

        best_bigram_score = 0.0
        for pos in word_pos_set:
            lookup_pos = 'V' if pos in ('t', 'i') else pos

            if prev_pos:
                prev_lookup = 'V' if prev_pos in ('t', 'i') else prev_pos
                p_given_prev = self.pos_bigrams.get((prev_lookup, lookup_pos), 0.001)
            else:
                p_given_prev = 0.1

            if next_pos:
                next_lookup = 'V' if next_pos in ('t', 'i') else next_pos
                p_next_given = self.pos_bigrams.get((lookup_pos, next_lookup), 0.001)
            else:
                p_next_given = 0.1

            bigram_score = p_given_prev * p_next_given
            if bigram_score > best_bigram_score:
                best_bigram_score = bigram_score

        if best_bigram_score > 0:
            pos_score = math.log10(best_bigram_score)
        else:
            pos_score = -4.0

        unigram_score = 0.0
        if self.unigram_prob and word_lower in self.unigram_prob:
            prob = self.unigram_prob[word_lower]
            if prob > 0:
                unigram_score = math.log10(prob)

        score = pos_score + unigram_score
        return score

    def _unigram_score(self, word_lower: str) -> float:
        """Get unigram probability score for a word."""
        import math
        if self.unigram_prob and word_lower in self.unigram_prob:
            prob = self.unigram_prob[word_lower]
            if prob > 0:
                # Convert to log scale, normalize to 0-2 range
                log_prob = math.log10(prob)  # -2 to -9 roughly
                return (log_prob + 9) * 0.2  # Maps -9->0, -2->1.4
        return 0.0

    def _log_decision(self, text: str, word_idx: int, original: str, scores: dict, chosen: str, prev_word: str | None, next_word: str | None):
        """Log homophone disambiguation decision to file for later analysis."""
        import json
        from datetime import datetime

        log_path = Path(__file__).parent.parent / "logs" / "homophone_decisions.jsonl"
        log_path.parent.mkdir(exist_ok=True)

        entry = {
            "timestamp": datetime.now().isoformat(),
            "text": text,
            "word_idx": word_idx,
            "original": original,
            "prev_word": prev_word,
            "next_word": next_word,
            "scores": {k: round(v, 4) for k, v in scores.items()},
            "chosen": chosen,
            "changed": chosen != original
        }

        try:
            with open(log_path, 'a') as f:
                f.write(json.dumps(entry) + '\n')
        except Exception:
            pass  # Don't let logging failures affect disambiguation

    def disambiguate(self, text: str) -> str:
        """Disambiguate homophones in text."""
        if not text.strip():
            return text

        # Preserve leading/trailing whitespace
        leading = len(text) - len(text.lstrip())
        trailing = len(text) - len(text.rstrip())
        prefix = text[:leading] if leading else ''
        suffix = text[-trailing:] if trailing else ''

        words = text.split()
        result = []

        # Get neighbor POS for all positions (single spaCy call)
        neighbor_pos = {}
        for i in range(len(words)):
            neighbor_pos[i] = self.get_neighbor_pos(words, i)

        for i, word in enumerate(words):
            word_lower = word.lower()
            homophones = self.homophones.get(word_lower)

            if homophones and len(homophones) > 1:
                prev_pos, next_pos = neighbor_pos[i]
                prev_word = words[i-1] if i > 0 else None
                next_word = words[i+1] if i < len(words)-1 else None

                # Score all candidates
                scores = {}
                for candidate in homophones:
                    scores[candidate] = self.score_candidate(candidate, prev_pos, next_pos, prev_word, next_word)

                # Find best - but keep original if tied (don't change on equal scores)
                best_word = word_lower
                best_score = scores[word_lower]
                for candidate, score in scores.items():
                    if score > best_score:  # Strictly greater - ties keep original
                        best_score = score
                        best_word = candidate

                # Log the decision for later analysis
                self._log_decision(text, i, word_lower, scores, best_word, prev_word, next_word)

                # Preserve capitalization
                if best_word != word_lower:
                    if word[0].isupper():
                        best_word = best_word.capitalize()
                    print(f"POS: {word} -> {best_word} (prev_word={prev_word}, next_word={next_word})", file=sys.stderr)
                    word = best_word

            result.append(word)

        return prefix + ' '.join(result) + suffix


def main():
    # Default paths
    script_dir = Path(__file__).parent
    lexicon_path = script_dir.parent / "tools" / "talkie.lex"
    unigram_path = script_dir.parent / "tools" / "unigram_probs.txt"
    bigram_path = script_dir.parent / "tools" / "pos-bigrams.tsv"
    word_bigram_path = script_dir.parent / "tools" / "word-bigrams.tsv"

    # Allow override from command line
    if len(sys.argv) >= 2:
        lexicon_path = Path(sys.argv[1])
    if len(sys.argv) >= 3:
        unigram_path = Path(sys.argv[2])
    if len(sys.argv) >= 4:
        bigram_path = Path(sys.argv[3])
    if len(sys.argv) >= 5:
        word_bigram_path = Path(sys.argv[4])

    if not lexicon_path.exists():
        print(f"Error: lexicon not found: {lexicon_path}", file=sys.stderr)
        sys.exit(1)

    if not unigram_path.exists():
        print(f"Warning: unigram probs not found: {unigram_path}", file=sys.stderr)
        unigram_path = None

    if not bigram_path.exists():
        print(f"Warning: POS bigrams not found: {bigram_path}", file=sys.stderr)
        bigram_path = None

    if not word_bigram_path.exists():
        print(f"Warning: word bigrams not found: {word_bigram_path}", file=sys.stderr)
        word_bigram_path = None

    print(f"POS: starting service...", file=sys.stderr)
    print(f"POS: lexicon={lexicon_path}", file=sys.stderr)
    print(f"POS: unigrams={unigram_path}", file=sys.stderr)
    print(f"POS: pos_bigrams={bigram_path}", file=sys.stderr)
    print(f"POS: word_bigrams={word_bigram_path}", file=sys.stderr)
    print(f"POS: spacy={'yes' if HAS_SPACY else 'no'}", file=sys.stderr)

    t0 = time.perf_counter()
    service = LexiconPOSService(
        str(lexicon_path),
        str(unigram_path) if unigram_path else None,
        str(bigram_path) if bigram_path else None,
        str(word_bigram_path) if word_bigram_path else None
    )
    elapsed = (time.perf_counter() - t0) * 1000
    print(f"POS: ready ({elapsed:.0f}ms)", file=sys.stderr)
    sys.stderr.flush()

    # Process stdin line by line
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        t0 = time.perf_counter()
        result = service.disambiguate(line)
        elapsed = (time.perf_counter() - t0) * 1000

        print(result, flush=True)
        print(f"POS: {elapsed:.1f}ms", file=sys.stderr)
        sys.stderr.flush()


if __name__ == '__main__':
    main()
