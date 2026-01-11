#!/usr/bin/env python3
"""Find phonetically similar words in pronunciation dictionaries.

Uses edit distance on phoneme sequences to find words that sound similar
to domain-specific vocabulary. This helps identify which common English
words the acoustic model might confuse with specialized terms.

Usage:
    ./phonetic_similarity.py critcl vosk portaudio
    ./phonetic_similarity.py --dict /path/to/en.dic word1 word2
"""

import argparse
import sys
from pathlib import Path
# Default dictionary paths
DEFAULT_DICTS = [
    Path.home() / "Downloads/vosk-model-en-us-0.22-compile/db/en.dic",
    Path.home() / "src/talkie/tools/base_missing.dic",
    Path.home() / "src/talkie/extra.dic",
]

# Common English words (top ~3000) - words the acoustic model strongly prefers
# From various frequency lists; used to flag likely confusions
COMMON_WORDS = {
    # Articles, pronouns, prepositions, conjunctions
    'a', 'an', 'the', 'and', 'or', 'but', 'if', 'then', 'than', 'that', 'this',
    'these', 'those', 'what', 'which', 'who', 'whom', 'whose', 'where', 'when',
    'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most', 'other',
    'some', 'such', 'no', 'not', 'only', 'own', 'same', 'so', 'as', 'at', 'by',
    'for', 'from', 'in', 'into', 'of', 'on', 'to', 'with', 'about', 'after',
    'before', 'between', 'through', 'during', 'without', 'again', 'against',
    # Common verbs
    'be', 'is', 'are', 'was', 'were', 'been', 'being', 'have', 'has', 'had',
    'do', 'does', 'did', 'done', 'doing', 'will', 'would', 'could', 'should',
    'may', 'might', 'must', 'shall', 'can', 'need', 'get', 'got', 'go', 'goes',
    'went', 'gone', 'going', 'come', 'came', 'coming', 'make', 'made', 'making',
    'take', 'took', 'taken', 'taking', 'give', 'gave', 'given', 'giving', 'see',
    'saw', 'seen', 'seeing', 'know', 'knew', 'known', 'knowing', 'think',
    'thought', 'thinking', 'want', 'wanted', 'wanting', 'use', 'used', 'using',
    'find', 'found', 'finding', 'tell', 'told', 'telling', 'ask', 'asked',
    'asking', 'work', 'worked', 'working', 'seem', 'seemed', 'seeming', 'feel',
    'felt', 'feeling', 'try', 'tried', 'trying', 'leave', 'left', 'leaving',
    'call', 'called', 'calling', 'keep', 'kept', 'keeping', 'let', 'put',
    'putting', 'begin', 'began', 'begun', 'beginning', 'show', 'showed',
    'shown', 'showing', 'hear', 'heard', 'hearing', 'play', 'played', 'playing',
    'run', 'ran', 'running', 'move', 'moved', 'moving', 'live', 'lived',
    'living', 'believe', 'believed', 'believing', 'hold', 'held', 'holding',
    'bring', 'brought', 'bringing', 'happen', 'happened', 'happening', 'write',
    'wrote', 'written', 'writing', 'provide', 'provided', 'providing', 'sit',
    'sat', 'sitting', 'stand', 'stood', 'standing', 'lose', 'lost', 'losing',
    'pay', 'paid', 'paying', 'meet', 'met', 'meeting', 'include', 'included',
    'including', 'continue', 'continued', 'continuing', 'set', 'setting',
    'learn', 'learned', 'learning', 'change', 'changed', 'changing', 'lead',
    'led', 'leading', 'understand', 'understood', 'understanding', 'watch',
    'watched', 'watching', 'follow', 'followed', 'following', 'stop', 'stopped',
    'stopping', 'create', 'created', 'creating', 'speak', 'spoke', 'spoken',
    'speaking', 'read', 'reading', 'allow', 'allowed', 'allowing', 'add',
    'added', 'adding', 'spend', 'spent', 'spending', 'grow', 'grew', 'grown',
    'growing', 'open', 'opened', 'opening', 'walk', 'walked', 'walking', 'win',
    'won', 'winning', 'offer', 'offered', 'offering', 'remember', 'remembered',
    'remembering', 'love', 'loved', 'loving', 'consider', 'considered',
    'considering', 'appear', 'appeared', 'appearing', 'buy', 'bought', 'buying',
    'wait', 'waited', 'waiting', 'serve', 'served', 'serving', 'die', 'died',
    'dying', 'send', 'sent', 'sending', 'expect', 'expected', 'expecting',
    'build', 'built', 'building', 'stay', 'stayed', 'staying', 'fall', 'fell',
    'fallen', 'falling', 'cut', 'cutting', 'reach', 'reached', 'reaching',
    'kill', 'killed', 'killing', 'remain', 'remained', 'remaining', 'suggest',
    'suggested', 'suggesting', 'raise', 'raised', 'raising', 'pass', 'passed',
    'passing', 'sell', 'sold', 'selling', 'require', 'required', 'requiring',
    'report', 'reported', 'reporting', 'decide', 'decided', 'deciding', 'pull',
    'pulled', 'pulling',
    # Common nouns
    'time', 'year', 'people', 'way', 'day', 'man', 'woman', 'child', 'children',
    'world', 'life', 'hand', 'part', 'place', 'case', 'week', 'company', 'system',
    'program', 'question', 'work', 'government', 'number', 'night', 'point',
    'home', 'water', 'room', 'mother', 'area', 'money', 'story', 'fact', 'month',
    'lot', 'right', 'study', 'book', 'eye', 'job', 'word', 'business', 'issue',
    'side', 'kind', 'head', 'house', 'service', 'friend', 'father', 'power',
    'hour', 'game', 'line', 'end', 'member', 'law', 'car', 'city', 'community',
    'name', 'president', 'team', 'minute', 'idea', 'kid', 'body', 'information',
    'back', 'parent', 'face', 'others', 'level', 'office', 'door', 'health',
    'person', 'art', 'war', 'history', 'party', 'result', 'change', 'morning',
    'reason', 'research', 'girl', 'guy', 'moment', 'air', 'teacher', 'force',
    'education', 'foot', 'boy', 'age', 'policy', 'process', 'music', 'market',
    'sense', 'nation', 'plan', 'college', 'interest', 'death', 'experience',
    'effect', 'use', 'class', 'control', 'care', 'field', 'development', 'role',
    'effort', 'rate', 'heart', 'drug', 'show', 'leader', 'light', 'voice',
    'wife', 'police', 'mind', 'difference', 'period', 'value', 'behavior',
    'structure', 'century', 'course', 'action', 'activity', 'population',
    'type', 'cover', 'food', 'practice', 'ground', 'form', 'support', 'event',
    'official', 'matter', 'center', 'couple', 'site', 'project', 'base', 'star',
    'table', 'need', 'court', 'record', 'risk', 'science', 'cost', 'position',
    'paper', 'music', 'nature', 'range', 'order', 'model', 'film', 'source',
    'movement', 'image', 'computer', 'focus', 'staff', 'truth', 'view', 'price',
    'data', 'amount', 'chance', 'society', 'section', 'answer', 'test', 'step',
    # Common adjectives
    'good', 'new', 'first', 'last', 'long', 'great', 'little', 'own', 'other',
    'old', 'right', 'big', 'high', 'different', 'small', 'large', 'next', 'early',
    'young', 'important', 'few', 'public', 'bad', 'same', 'able', 'free', 'sure',
    'clear', 'full', 'special', 'real', 'best', 'better', 'certain', 'possible',
    'late', 'hard', 'major', 'whole', 'local', 'true', 'private', 'past',
    'foreign', 'fine', 'common', 'poor', 'natural', 'significant', 'similar',
    'hot', 'dead', 'central', 'happy', 'serious', 'ready', 'simple', 'left',
    'physical', 'general', 'environmental', 'financial', 'blue', 'democratic',
    'dark', 'medical', 'wrong', 'particular', 'international', 'strong',
    'available', 'single', 'current', 'traditional', 'likely', 'federal',
    'cultural', 'religious', 'cold', 'short', 'successful', 'red', 'economic',
    'critical', 'final', 'main', 'sorry', 'difficult', 'active', 'ahead',
    # Common adverbs
    'up', 'out', 'down', 'just', 'now', 'also', 'very', 'well', 'still', 'even',
    'back', 'here', 'there', 'too', 'really', 'most', 'always', 'never', 'often',
    'much', 'far', 'away', 'over', 'off', 'today', 'ever', 'yet', 'already',
    'soon', 'together', 'around', 'however', 'later', 'always', 'perhaps',
    'probably', 'actually', 'especially', 'certainly', 'usually', 'clearly',
    # Technology/computing (likely domain confusion)
    'computer', 'system', 'program', 'software', 'data', 'code', 'file', 'audio',
    'video', 'digital', 'network', 'internet', 'online', 'server', 'port',
    'protocol', 'critical', 'process', 'thread', 'memory', 'buffer', 'cache',
    'interface', 'module', 'package', 'library', 'function', 'method', 'class',
    'object', 'string', 'array', 'list', 'type', 'value', 'error', 'exception',
    'debug', 'test', 'build', 'compile', 'script', 'command', 'shell', 'terminal',
}


def load_dictionary(dict_path: Path) -> dict[str, list[str]]:
    """Load pronunciation dictionary into word -> [phonemes] mapping."""
    pronunciations = {}

    if not dict_path.exists():
        return pronunciations

    with open(dict_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            parts = line.split()
            if len(parts) < 2:
                continue

            word = parts[0].lower()
            phonemes = parts[1:]

            # Handle multiple pronunciations (word, word(2), word(3), etc.)
            base_word = word.split('(')[0]

            if base_word not in pronunciations:
                pronunciations[base_word] = phonemes

    return pronunciations


def phoneme_distance(p1: list[str], p2: list[str]) -> int:
    """Compute Levenshtein distance between two phoneme sequences."""
    m, n = len(p1), len(p2)

    # Use two rows for space efficiency
    prev = list(range(n + 1))
    curr = [0] * (n + 1)

    for i in range(1, m + 1):
        curr[0] = i
        for j in range(1, n + 1):
            if p1[i-1] == p2[j-1]:
                curr[j] = prev[j-1]
            else:
                curr[j] = 1 + min(prev[j], curr[j-1], prev[j-1])
        prev, curr = curr, prev

    return prev[n]


def weighted_phoneme_distance(p1: list[str], p2: list[str]) -> float:
    """Compute weighted distance with lower cost for similar phonemes."""
    # Phoneme similarity groups (substitutions within group cost 0.5)
    SIMILAR_GROUPS = [
        # Vowels
        {'@', 'V', 'I', 'E', 'i', 'u'},  # Reduced vowels
        {'A', 'O', 'aU', 'oU'},  # Back vowels
        {'eI', 'aI', 'OI'},  # Diphthongs
        # Consonants
        {'t', 'd', '4'},  # Alveolar stops + tap (tap is allophone of t/d)
        {'p', 'b'},  # Bilabial stops
        {'k', 'g'},  # Velar stops
        {'s', 'z'},  # Alveolar fricatives
        {'S', 'Z'},  # Post-alveolar fricatives
        {'f', 'v'},  # Labiodental fricatives
        {'T', 'D'},  # Dental fricatives
        {'m', 'n', 'N'},  # Nasals
        {'l', 'r'},  # Liquids
    ]

    # Reduced/weak vowels - inserting/deleting these costs less (0.5)
    # These are often elided or barely pronounced in connected speech
    REDUCED_VOWELS = {'@', 'V', 'I', 'i', 'u', '3`'}

    # Build phoneme -> group mapping
    phoneme_group = {}
    for i, group in enumerate(SIMILAR_GROUPS):
        for p in group:
            phoneme_group[p] = i

    def sub_cost(a, b):
        if a == b:
            return 0
        ga = phoneme_group.get(a, -1)
        gb = phoneme_group.get(b, -2)
        return 0.5 if ga == gb and ga >= 0 else 1.0

    def indel_cost(p):
        """Cost for inserting or deleting phoneme p."""
        return 0.5 if p in REDUCED_VOWELS else 1.0

    m, n = len(p1), len(p2)
    # Initialize with weighted costs for deletions from p1
    prev = [0.0]
    for j in range(1, n + 1):
        prev.append(prev[j-1] + indel_cost(p2[j-1]))

    curr = [0.0] * (n + 1)

    for i in range(1, m + 1):
        curr[0] = prev[0] + indel_cost(p1[i-1])  # Deletion cost from p1
        for j in range(1, n + 1):
            curr[j] = min(
                prev[j] + indel_cost(p1[i-1]),  # Delete from p1
                curr[j-1] + indel_cost(p2[j-1]),  # Insert from p2
                prev[j-1] + sub_cost(p1[i-1], p2[j-1])  # Substitute
            )
        prev, curr = curr, prev

    return prev[n]


def find_similar_words(
    target_word: str,
    target_phonemes: list[str],
    dictionary: dict[str, list[str]],
    top_n: int = 20,
    max_distance: float = 4.0,
    use_weighted: bool = True
) -> list[tuple[str, list[str], float]]:
    """Find words with similar pronunciation to target."""

    dist_fn = weighted_phoneme_distance if use_weighted else phoneme_distance

    # Collect all matches within threshold
    results = []

    for word, phonemes in dictionary.items():
        if word == target_word:
            continue

        dist = dist_fn(target_phonemes, phonemes)

        if dist <= max_distance:
            results.append((dist, word, phonemes))

    # Sort by distance, then alphabetically
    results.sort(key=lambda x: (x[0], x[1]))

    # Return top N
    return [(w, p, d) for d, w, p in results[:top_n]]


def format_phonemes(phonemes: list[str]) -> str:
    """Format phoneme list for display."""
    return ' '.join(phonemes)


def main():
    parser = argparse.ArgumentParser(
        description='Find phonetically similar words in pronunciation dictionary'
    )
    parser.add_argument('words', nargs='+', help='Words to find similar matches for')
    parser.add_argument('--dict', '-d', action='append', dest='dicts',
                        help='Path to pronunciation dictionary (can specify multiple)')
    parser.add_argument('--top', '-n', type=int, default=25,
                        help='Number of similar words to show (default: 25)')
    parser.add_argument('--common-only', '-c', action='store_true',
                        help='Only show common English words (likely confusions)')
    parser.add_argument('--max-distance', '-m', type=float, default=3.0,
                        help='Maximum phoneme edit distance (default: 3.0)')
    parser.add_argument('--unweighted', '-u', action='store_true',
                        help='Use unweighted edit distance')
    parser.add_argument('--quiet', '-q', action='store_true',
                        help='Only show word matches, not phonemes')

    args = parser.parse_args()

    # Load dictionaries
    dict_paths = [Path(d) for d in args.dicts] if args.dicts else DEFAULT_DICTS

    print(f"Loading dictionaries...", file=sys.stderr)
    dictionary = {}
    for dict_path in dict_paths:
        if dict_path.exists():
            loaded = load_dictionary(dict_path)
            print(f"  {dict_path.name}: {len(loaded)} words", file=sys.stderr)
            dictionary.update(loaded)

    print(f"Total: {len(dictionary)} pronunciations\n", file=sys.stderr)

    if not dictionary:
        print("Error: No dictionaries found", file=sys.stderr)
        sys.exit(1)

    # Process each target word
    for target in args.words:
        target_lower = target.lower()

        if target_lower not in dictionary:
            print(f"'{target}': Not found in dictionary\n")
            continue

        target_phonemes = dictionary[target_lower]

        print(f"'{target}' /{format_phonemes(target_phonemes)}/")
        print("-" * 60)

        similar = find_similar_words(
            target_lower,
            target_phonemes,
            dictionary,
            top_n=args.top,
            max_distance=args.max_distance,
            use_weighted=not args.unweighted
        )

        # Filter to common words only if requested
        if args.common_only:
            similar = [(w, p, d) for w, p, d in similar if w in COMMON_WORDS]

        if not similar:
            print("  No similar words found within distance threshold")
        else:
            for word, phonemes, dist in similar:
                # Flag common words that are likely confusions
                marker = " *" if word in COMMON_WORDS else ""
                if args.quiet:
                    print(f"  {word} ({dist:.1f}){marker}")
                else:
                    print(f"  {dist:.1f}  {word:20} /{format_phonemes(phonemes)}/{marker}")

            # Show legend if any common words found
            common_count = sum(1 for w, _, _ in similar if w in COMMON_WORDS)
            if common_count > 0 and not args.common_only:
                print(f"\n  (* = common word, likely confusion)")

        print()


if __name__ == '__main__':
    main()
