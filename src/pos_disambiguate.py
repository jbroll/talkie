#!/usr/bin/env python3
"""POS-based homophone disambiguation for speech recognition.

Uses part-of-speech tagging to disambiguate homophones based on
grammatical context from recent utterances.

Homophones are discovered dynamically from the pronunciation dictionary
by finding words with identical pronunciations.

Word frequencies are derived from the model's ARPA language model file,
not from an ad-hoc curated list.
"""

import sys
import time
from pathlib import Path
from collections import defaultdict

# Import phonetic similarity functions from tools
_tools_dir = Path(__file__).parent.parent / "tools"
if _tools_dir.exists():
    sys.path.insert(0, str(_tools_dir))
    try:
        from phonetic_similarity import weighted_phoneme_distance, load_dictionary
        HAS_PHONETIC = True
    except ImportError:
        HAS_PHONETIC = False
else:
    HAS_PHONETIC = False

# Try spaCy first, fall back to simple rules
try:
    import spacy
    nlp = spacy.load("en_core_web_sm")
    POS_ENGINE = "spacy"
except (ImportError, OSError):
    nlp = None
    POS_ENGINE = "rules"


class HomophoneDisambiguator:
    def __init__(self, dic_path: Path | str | None = None,
                 vocab_path: Path | str | None = None,
                 arpa_path: Path | str | None = None,
                 max_distance: float = 1.0):
        self.homophones = defaultdict(set)  # word -> {homophones}
        self.word_to_pron = {}  # word -> [phonemes]
        self.word_prob = {}  # word -> log10 probability from ARPA
        self.context_buffer = []  # recent utterances
        self.max_context = 5  # keep last N utterances
        self.max_distance = max_distance

        # Default probability threshold: -6.0 means ~1 in 1 million
        # Words with higher (less negative) prob are more common
        self.common_threshold = -5.5  # adjustable

        if arpa_path:
            self.load_arpa_probabilities(arpa_path)
        if dic_path:
            self.load_dictionary(dic_path)
        if vocab_path:
            self.build_homophone_index(vocab_path)

    def load_arpa_probabilities(self, arpa_path: Path | str):
        """Load unigram probabilities from ARPA language model file."""
        t0 = time.perf_counter()
        arpa_path = Path(arpa_path)
        if not arpa_path.exists():
            print(f"Warning: ARPA file not found: {arpa_path}", file=sys.stderr)
            return

        print(f"POS: loading word probabilities from {arpa_path.name}...", file=sys.stderr)

        in_unigrams = False
        count = 0

        with open(arpa_path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()

                if line == '\\1-grams:':
                    in_unigrams = True
                    continue
                elif line.startswith('\\') and line.endswith(':'):
                    # Hit 2-grams or higher, stop
                    if in_unigrams:
                        break
                    continue

                if in_unigrams and line:
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        try:
                            prob = float(parts[0])
                            word = parts[1].lower()
                            # Skip special tokens
                            if not word.startswith('<') and not word.startswith('#'):
                                self.word_prob[word] = prob
                                count += 1
                        except ValueError:
                            continue

        elapsed = time.perf_counter() - t0
        print(f"POS: loaded {count} word probabilities ({elapsed*1000:.0f}ms)", file=sys.stderr)

        # Show probability distribution
        if self.word_prob:
            probs = sorted(self.word_prob.values())
            p10 = probs[len(probs)//10]
            p50 = probs[len(probs)//2]
            p90 = probs[len(probs)*9//10]
            print(f"POS: probability distribution: 10%={p10:.2f} 50%={p50:.2f} 90%={p90:.2f}", file=sys.stderr)

    def is_common_word(self, word: str) -> bool:
        """Check if word is common based on LM probability."""
        word = word.lower()
        if word not in self.word_prob:
            return False
        return self.word_prob[word] > self.common_threshold

    def get_word_prob(self, word: str) -> float:
        """Get word probability (log10). Returns -99 for unknown words."""
        return self.word_prob.get(word.lower(), -99.0)

    def load_dictionary(self, dic_path: Path | str):
        """Load pronunciation dictionary."""
        t0 = time.perf_counter()
        dic_path = Path(dic_path)
        if not dic_path.exists():
            print(f"Warning: Dictionary not found: {dic_path}", file=sys.stderr)
            return

        if HAS_PHONETIC:
            self.word_to_pron = load_dictionary(dic_path)
            elapsed = time.perf_counter() - t0
            print(f"POS: loaded {len(self.word_to_pron)} pronunciations ({elapsed*1000:.0f}ms)", file=sys.stderr)
        else:
            # Fallback: just load words without phoneme parsing
            with open(dic_path, 'r', encoding='utf-8', errors='replace') as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 2:
                        word = parts[0].lower()
                        if '(' in word:
                            word = word.split('(')[0]
                        self.word_to_pron[word] = parts[1:]
            elapsed = time.perf_counter() - t0
            print(f"POS: loaded {len(self.word_to_pron)} words ({elapsed*1000:.0f}ms, no phonetic module)", file=sys.stderr)

    def build_homophone_index(self, vocab_path: Path | str):
        """Build homophone index from vocabulary file, with caching."""
        import json
        import hashlib

        t0 = time.perf_counter()
        vocab_path = Path(vocab_path)
        if not vocab_path.exists():
            print(f"Warning: Vocabulary not found: {vocab_path}", file=sys.stderr)
            return

        if not HAS_PHONETIC:
            print("Warning: phonetic_similarity module not available", file=sys.stderr)
            return

        # Check for cached index
        cache_dir = Path.home() / ".cache" / "talkie"
        cache_dir.mkdir(parents=True, exist_ok=True)

        # Cache key based on vocab file and max_distance
        vocab_hash = hashlib.md5(vocab_path.read_bytes()).hexdigest()[:8]
        cache_file = cache_dir / f"homophones_{vocab_hash}_{self.max_distance}.json"

        if cache_file.exists():
            try:
                with open(cache_file, 'r') as f:
                    cached = json.load(f)
                for word, homophones in cached.items():
                    self.homophones[word] = set(homophones)
                elapsed = time.perf_counter() - t0
                print(f"POS: loaded {len(self.homophones)} cached homophones ({elapsed*1000:.0f}ms)", file=sys.stderr)
                return
            except Exception as e:
                print(f"POS: cache load failed: {e}", file=sys.stderr)

        # Load vocabulary
        vocab = set()
        with open(vocab_path, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if parts and not parts[0].startswith('<') and not parts[0].startswith('#'):
                    vocab.add(parts[0].lower())

        # For large vocabularies, limit to shorter words (most homophones are short)
        MAX_PHONEMES = 4  # Only check words with <= 4 phonemes
        vocab_with_pron = [(w, self.word_to_pron[w]) for w in vocab
                           if w in self.word_to_pron and len(self.word_to_pron[w]) <= MAX_PHONEMES]
        print(f"POS: building homophone index for {len(vocab_with_pron)} short words (of {len(vocab)} vocab)...",
              file=sys.stderr)

        # Group words by exact pronunciation for O(n) exact homophone detection
        by_pron = defaultdict(set)
        for word, pron in vocab_with_pron:
            pron_key = tuple(pron)
            by_pron[pron_key].add(word)

        # Words with same pronunciation are homophones
        count = 0
        useful_groups = 0
        for pron_key, words in by_pron.items():
            if len(words) > 1:
                for word in words:
                    self.homophones[word] = words
                    count += 1

                # Count "useful" groups: at least 2 common words
                if self.word_prob:
                    common_in_group = sum(1 for w in words if self.is_common_word(w))
                    if common_in_group >= 2:
                        useful_groups += 1

        print(f"POS: found {count} exact homophones (same pronunciation)", file=sys.stderr)
        if self.word_prob:
            print(f"POS: {useful_groups} homophone groups have 2+ common words", file=sys.stderr)

        # Cache the results
        try:
            cache_data = {w: list(h) for w, h in self.homophones.items()}
            with open(cache_file, 'w') as f:
                json.dump(cache_data, f)
            print(f"POS: cached to {cache_file}", file=sys.stderr)
        except Exception as e:
            print(f"POS: cache save failed: {e}", file=sys.stderr)

    def get_homophones(self, word: str) -> set:
        """Get homophones for a word."""
        return self.homophones.get(word.lower(), set())

    def pos_tag(self, text: str) -> list[tuple[str, str]]:
        """POS tag text, returns [(word, tag), ...]"""
        if nlp:
            doc = nlp(text)
            return [(token.text, token.pos_) for token in doc]
        else:
            return self._simple_pos_tag(text)

    def _simple_pos_tag(self, text: str) -> list[tuple[str, str]]:
        """Simple rule-based POS tagger for common cases."""
        words = text.split()
        result = []

        determiners = {'the', 'a', 'an', 'this', 'that', 'these', 'those',
                       'my', 'your', 'his', 'her', 'its', 'our', 'their'}
        prepositions = {'in', 'on', 'at', 'to', 'for', 'with', 'by', 'from',
                        'of', 'about', 'into', 'through', 'during', 'before',
                        'after', 'above', 'below', 'between', 'under', 'over'}
        pronouns = {'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him',
                    'her', 'us', 'them', 'who', 'what', 'which', 'that'}
        common_verbs = {'is', 'are', 'was', 'were', 'be', 'been', 'being',
                        'have', 'has', 'had', 'do', 'does', 'did', 'will',
                        'would', 'could', 'should', 'may', 'might', 'must',
                        'can', 'go', 'get', 'make', 'run', 'see', 'know'}

        for i, word in enumerate(words):
            w = word.lower().rstrip('.,!?')
            prev = words[i-1].lower() if i > 0 else None

            if w in determiners:
                tag = 'DET'
            elif w in prepositions:
                tag = 'ADP'
            elif w in pronouns:
                tag = 'PRON'
            elif w in common_verbs:
                tag = 'VERB'
            elif prev in determiners or prev in prepositions:
                tag = 'NOUN'  # after determiner/preposition, likely noun
            elif prev in pronouns:
                tag = 'VERB'  # after pronoun, likely verb
            else:
                tag = 'X'  # unknown

            result.append((word, tag))

        return result

    def add_context(self, utterance: str):
        """Add utterance to context buffer."""
        self.context_buffer.append(utterance)
        if len(self.context_buffer) > self.max_context:
            self.context_buffer.pop(0)

    def get_context_text(self) -> str:
        """Get recent context as single string."""
        return ' '.join(self.context_buffer)

    def disambiguate(self, text: str, debug: bool = True) -> str:
        """Disambiguate homophones in text using POS context."""
        if not text.strip():
            return text

        words = text.split()
        context = self.get_context_text()
        full_text = f"{context} {text}".strip()

        # POS tag the full context + current text
        tagged = self.pos_tag(full_text)

        # Find where current text starts in tagged output
        context_word_count = len(context.split()) if context else 0
        current_tagged = tagged[context_word_count:]

        if debug:
            print(f"POS DEBUG: input='{text}'", file=sys.stderr)
            print(f"POS DEBUG: context='{context}'", file=sys.stderr)
            print(f"POS DEBUG: tagged={current_tagged}", file=sys.stderr)

        result_words = []
        changes = []

        for i, word in enumerate(words):
            homophones = self.get_homophones(word)

            if homophones and len(homophones) > 1:
                # Get surrounding context
                prev_word = words[i-1].lower() if i > 0 else None
                next_word = words[i+1].lower() if i < len(words)-1 else None
                prev_pos = current_tagged[i-1][1] if i > 0 and i-1 < len(current_tagged) else None
                next_pos = current_tagged[i+1][1] if i < len(words)-1 and i+1 < len(current_tagged) else None
                current_pos = current_tagged[i][1] if i < len(current_tagged) else 'X'

                # Check if a different homophone fits better
                best_word = word.lower()
                best_score = self._context_score(word.lower(), prev_word, next_word, prev_pos, next_pos)

                if debug:
                    print(f"POS DEBUG: '{word}' pos={current_pos} prev={prev_word}({prev_pos}) next={next_word}({next_pos})",
                          file=sys.stderr)
                    print(f"POS DEBUG:   homophones={homophones} score={best_score}", file=sys.stderr)

                for alt in homophones:
                    if alt != word.lower():
                        alt_score = self._context_score(alt, prev_word, next_word, prev_pos, next_pos)
                        if debug:
                            print(f"POS DEBUG:   alt='{alt}' score={alt_score}",
                                  file=sys.stderr)
                        if alt_score > best_score:
                            best_score = alt_score
                            best_word = alt

                if best_word != word.lower():
                    changes.append(f"{word}->{best_word}")
                    # Preserve capitalization
                    if word[0].isupper():
                        best_word = best_word.capitalize()
                    word = best_word

            result_words.append(word)

        result = ' '.join(result_words)

        if debug and changes:
            print(f"POS DEBUG: changes={changes}", file=sys.stderr)
            print(f"POS DEBUG: result='{result}'", file=sys.stderr)

        # Add to context for next utterance
        self.add_context(result)

        return result

    def _context_score(self, word: str, prev_word: str, next_word: str,
                       prev_pos: str, next_pos: str) -> int:
        """Score how well a word fits its context."""
        word = word.lower()
        score = 0

        # Context rules for common homophones
        # NOTE: Rules only apply when we have good POS tags (not 'X')
        # Without spaCy, the fallback tagger is too weak for reliable disambiguation
        rules = {
            # their/there/they're
            'their': [
                (lambda p, n, pp, np: np in ['NOUN', 'ADJ'], 3),  # their + noun/adj
                # Removed overly broad rule that triggered on any non-be-verb next word
            ],
            'there': [
                (lambda p, n, pp, np: n in ['is', 'are', 'was', 'were'], 3),  # there is/are
                (lambda p, n, pp, np: pp == 'ADP', 2),  # preposition + there (over there)
            ],
            "they're": [
                (lambda p, n, pp, np: np == 'VERB' or np == 'ADV', 3),  # they're + verb/adv
                (lambda p, n, pp, np: n in ['going', 'coming', 'doing', 'being', 'not', 'so', 'very', 'really', 'always', 'never'], 3),
            ],

            # your/you're
            'your': [
                (lambda p, n, pp, np: np in ['NOUN', 'ADJ'], 3),
            ],
            "you're": [
                (lambda p, n, pp, np: np in ['VERB', 'ADV', 'ADJ'], 3),
                (lambda p, n, pp, np: n in ['going', 'not', 'so', 'very', 'right', 'welcome'], 3),
            ],

            # its/it's
            'its': [
                (lambda p, n, pp, np: np in ['NOUN', 'ADJ'], 3),
            ],
            "it's": [
                (lambda p, n, pp, np: np in ['VERB', 'ADV', 'ADJ', 'DET'], 3),
                (lambda p, n, pp, np: n in ['a', 'the', 'not', 'been', 'going', 'time', 'okay', 'fine', 'good', 'bad'], 3),
            ],

            # to/too/two
            'to': [
                (lambda p, n, pp, np: np == 'VERB', 3),  # to + verb (infinitive)
                (lambda p, n, pp, np: n == 'the' or np == 'DET', 2),  # to the
            ],
            'too': [
                (lambda p, n, pp, np: np == 'ADJ' or np == 'ADV', 3),  # too + adj/adv
                (lambda p, n, pp, np: p in ['me', 'you', 'him', 'her', 'us', 'them'], 2),  # me too
                (lambda p, n, pp, np: n is None, 1),  # end of sentence
            ],
            'two': [
                (lambda p, n, pp, np: np == 'NOUN', 3),  # two + noun
                (lambda p, n, pp, np: pp in ['NUM', 'DET'], 2),
            ],

            # hear/here
            'hear': [
                (lambda p, n, pp, np: pp in ['VERB', 'AUX'] or p in ['can', "can't", 'could', "couldn't", 'to', 'not', "don't", "didn't"], 3),
                (lambda p, n, pp, np: np == 'PRON' or n in ['you', 'me', 'him', 'her', 'it', 'them', 'that', 'this'], 2),
            ],
            'here': [
                (lambda p, n, pp, np: p in ['over', 'right', 'come', 'came', 'is', 'are', 'was', 'were'], 3),
                (lambda p, n, pp, np: n is None or n in ['is', 'are', 'we', 'i', 'you', 'it'], 1),
            ],

            # know/no
            'know': [
                (lambda p, n, pp, np: pp in ['VERB', 'AUX', 'PRON'] or p in ['i', 'you', 'we', 'they', "don't", "didn't", 'to', 'not'], 3),
            ],
            'no': [
                (lambda p, n, pp, np: np == 'NOUN', 2),  # no + noun
                (lambda p, n, pp, np: n is None, 1),  # sentence start or standalone
                (lambda p, n, pp, np: p is None, 2),  # sentence start
            ],

            # right/write
            'right': [
                (lambda p, n, pp, np: p in ['all', "that's", 'is', 'are', "you're", 'thats'], 3),
                (lambda p, n, pp, np: np == 'NOUN' or n in ['now', 'here', 'there', 'away'], 2),
            ],
            'write': [
                (lambda p, n, pp, np: pp in ['VERB', 'AUX'] or p in ['to', 'can', 'could', 'will', 'would', "don't", 'please'], 3),
            ],

            # by/buy/bye
            'by': [
                (lambda p, n, pp, np: np in ['NOUN', 'DET', 'PRON', 'PROPN'] or n == 'the', 2),
            ],
            'buy': [
                (lambda p, n, pp, np: pp in ['VERB', 'AUX'] or p in ['to', 'can', 'could', 'will', 'would', "don't", 'please', "let's", 'want'], 3),
            ],
            'bye': [
                (lambda p, n, pp, np: n is None or p == 'good', 3),
            ],
        }

        if word in rules:
            for condition, points in rules[word]:
                try:
                    if condition(prev_word, next_word, prev_pos, next_pos):
                        score += points
                except:
                    pass

        return score

    def _pos_score(self, word: str, pos: str) -> int:
        """Score how well a word fits a POS tag."""
        word = word.lower()

        # Common word -> expected POS mappings
        pos_hints = {
            # their/there/they're
            'their': ['DET', 'PRON'],      # possessive determiner
            'there': ['ADV', 'PRON'],       # adverb or existential
            "they're": ['PRON'],            # pronoun (they are)

            # to/too/two
            'to': ['ADP', 'PART'],          # preposition or infinitive
            'too': ['ADV'],                 # adverb
            'two': ['NUM', 'NOUN'],         # number

            # your/you're
            'your': ['DET', 'PRON'],        # possessive
            "you're": ['PRON'],             # pronoun (you are)

            # its/it's
            'its': ['DET', 'PRON'],         # possessive
            "it's": ['PRON'],               # pronoun (it is)

            # hear/here
            'hear': ['VERB'],
            'here': ['ADV'],

            # right/write
            'right': ['ADJ', 'ADV', 'NOUN'],
            'write': ['VERB'],

            # know/no
            'know': ['VERB'],
            'no': ['DET', 'ADV', 'INTJ'],

            # new/knew
            'new': ['ADJ'],
            'knew': ['VERB'],

            # by/buy/bye
            'by': ['ADP'],
            'buy': ['VERB'],
            'bye': ['INTJ', 'NOUN'],

            # for/four
            'for': ['ADP'],
            'four': ['NUM'],

            # won/one
            'won': ['VERB'],
            'one': ['NUM', 'PRON'],

            # sun/son
            'sun': ['NOUN'],
            'son': ['NOUN'],  # both nouns, can't disambiguate easily

            # sea/see
            'sea': ['NOUN'],
            'see': ['VERB'],

            # be/bee
            'be': ['VERB', 'AUX'],
            'bee': ['NOUN'],
        }

        expected = pos_hints.get(word, [])
        if pos in expected:
            return 2  # strong match
        elif not expected:
            return 1  # no preference
        else:
            return 0  # mismatch


# Global instance
_disambiguator = None

def get_disambiguator(dic_path: Path | str | None = None) -> HomophoneDisambiguator:
    """Get or create the global disambiguator instance."""
    global _disambiguator
    if _disambiguator is None:
        _disambiguator = HomophoneDisambiguator(dic_path)
    return _disambiguator

def disambiguate(text: str, debug: bool = True) -> str:
    """Disambiguate homophones in text."""
    return get_disambiguator().disambiguate(text, debug=debug)


if __name__ == "__main__":
    # Test mode
    import sys

    # Try to find dictionary
    dic_paths = [
        Path.home() / "vosk-lgraph-compile/db/en.dic",
        Path.home() / "Downloads/vosk-model-en-us-0.22-compile/db/en.dic",
        Path("/usr/share/vosk/models/en.dic"),
    ]

    dic_path = None
    for p in dic_paths:
        if p.exists():
            dic_path = p
            break

    disambig = HomophoneDisambiguator(dic_path)

    # Test sentences
    tests = [
        "I went to there house",
        "there going to the store",
        "I can here you",
        "I want to by a car",
        "its a nice day",
        "I no the answer",
        "I want too go",
    ]

    print("\n=== Homophone Disambiguation Tests ===\n")
    for test in tests:
        result = disambig.disambiguate(test, debug=False)
        if result != test:
            print(f"  '{test}'")
            print(f"  -> '{result}'")
            print()
        else:
            print(f"  '{test}' (unchanged)")
            print()
