#!/usr/bin/env python3
"""
GEC Model Comparison Framework

Tests multiple grammar/spelling correction models against a comprehensive test set.
Measures accuracy and latency for each model.
"""

import json
import time
import statistics
import sys
from pathlib import Path
from dataclasses import dataclass
from typing import Callable, Optional

# =============================================================================
# TEST SET DEFINITION
# =============================================================================

@dataclass
class TestCase:
    """A single test case with input, expected output, and category."""
    input: str
    expected: str
    category: str
    notes: str = ""

# Comprehensive test set organized by category
TEST_CASES = [
    # -------------------------------------------------------------------------
    # HOMOPHONES: their/there/they're
    # -------------------------------------------------------------------------
    TestCase("I went to there house", "I went to their house", "homophone", "there→their"),
    TestCase("Their going to the park", "They're going to the park", "homophone", "their→they're"),
    TestCase("Put it over their", "Put it over there", "homophone", "their→there"),
    TestCase("There dog is cute", "Their dog is cute", "homophone", "there→their"),
    TestCase("I think there right", "I think they're right", "homophone", "there→they're"),
    TestCase("Their horses were stored in the barn over there", "Their horses were stored in the barn over there", "homophone", "correct - no change"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: your/you're
    # -------------------------------------------------------------------------
    TestCase("Your going to love this", "You're going to love this", "homophone", "your→you're"),
    TestCase("Is that you're car", "Is that your car", "homophone", "you're→your"),
    TestCase("Your the best", "You're the best", "homophone", "your→you're"),
    TestCase("I like your style", "I like your style", "homophone", "correct - no change"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: its/it's
    # -------------------------------------------------------------------------
    TestCase("I know its wrong", "I know it's wrong", "homophone", "its→it's"),
    TestCase("The dog wagged it's tail", "The dog wagged its tail", "homophone", "it's→its"),
    TestCase("Its a beautiful day", "It's a beautiful day", "homophone", "its→it's"),
    TestCase("The cat licked its paw", "The cat licked its paw", "homophone", "correct - no change"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: to/too/two
    # -------------------------------------------------------------------------
    TestCase("I went too the store", "I went to the store", "homophone", "too→to"),
    TestCase("Me to", "Me too", "homophone", "to→too"),
    TestCase("I have to cats", "I have two cats", "homophone", "to→two"),
    TestCase("That is to much", "That is too much", "homophone", "to→too"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: know/no
    # -------------------------------------------------------------------------
    TestCase("I no what you mean", "I know what you mean", "homophone", "no→know"),
    TestCase("Do you no the answer", "Do you know the answer", "homophone", "no→know"),
    TestCase("Know thanks", "No thanks", "homophone", "know→no"),
    TestCase("I know nothing", "I know nothing", "homophone", "correct - no change"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: here/hear
    # -------------------------------------------------------------------------
    TestCase("I can here you clearly", "I can hear you clearly", "homophone", "here→hear"),
    TestCase("Come hear right now", "Come here right now", "homophone", "hear→here"),
    TestCase("Did you here that", "Did you hear that", "homophone", "here→hear"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: write/right
    # -------------------------------------------------------------------------
    TestCase("Write the answer write now", "Write the answer right now", "homophone", "write→right"),
    TestCase("Turn write at the corner", "Turn right at the corner", "homophone", "write→right"),
    TestCase("You are write about that", "You are right about that", "homophone", "write→right"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: weather/whether
    # -------------------------------------------------------------------------
    TestCase("The whether is nice today", "The weather is nice today", "homophone", "whether→weather"),
    TestCase("I wonder weather it will rain", "I wonder whether it will rain", "homophone", "weather→whether"),
    TestCase("Check the whether forecast", "Check the weather forecast", "homophone", "whether→weather"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: through/threw
    # -------------------------------------------------------------------------
    TestCase("I through the ball", "I threw the ball", "homophone", "through→threw"),
    TestCase("He threw the window", "He threw through the window", "homophone", "context needed"),
    TestCase("Walk threw the door", "Walk through the door", "homophone", "threw→through"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: hole/whole
    # -------------------------------------------------------------------------
    TestCase("The hole thing was wrong", "The whole thing was wrong", "homophone", "hole→whole"),
    TestCase("There is a whole in my sock", "There is a hole in my sock", "homophone", "whole→hole"),
    TestCase("I ate the hole pizza", "I ate the whole pizza", "homophone", "hole→whole"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: by/buy/bye
    # -------------------------------------------------------------------------
    TestCase("I want to by a car", "I want to buy a car", "homophone", "by→buy"),
    TestCase("Say good buy", "Say goodbye", "homophone", "buy→bye (or goodbye)"),
    TestCase("Stand buy the door", "Stand by the door", "homophone", "buy→by"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: were/where/we're
    # -------------------------------------------------------------------------
    TestCase("Were are you going", "Where are you going", "homophone", "were→where"),
    TestCase("Where going home", "We're going home", "homophone", "where→we're"),
    TestCase("They where happy", "They were happy", "homophone", "where→were"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: affect/effect
    # -------------------------------------------------------------------------
    TestCase("It will effect the outcome", "It will affect the outcome", "homophone", "effect→affect"),
    TestCase("The affect was immediate", "The effect was immediate", "homophone", "affect→effect"),

    # -------------------------------------------------------------------------
    # HOMOPHONES: accept/except
    # -------------------------------------------------------------------------
    TestCase("I except your apology", "I accept your apology", "homophone", "except→accept"),
    TestCase("Everyone accept him came", "Everyone except him came", "homophone", "accept→except"),

    # -------------------------------------------------------------------------
    # GRAMMAR: Subject-verb agreement
    # -------------------------------------------------------------------------
    TestCase("She have been working hard", "She has been working hard", "grammar", "have→has"),
    TestCase("They was going to the store", "They were going to the store", "grammar", "was→were"),
    TestCase("He dont understand", "He doesn't understand", "grammar", "dont→doesn't"),
    TestCase("I has a question", "I have a question", "grammar", "has→have"),
    TestCase("The dogs runs fast", "The dogs run fast", "grammar", "runs→run"),

    # -------------------------------------------------------------------------
    # GRAMMAR: Verb tense
    # -------------------------------------------------------------------------
    TestCase("I seen him yesterday", "I saw him yesterday", "grammar", "seen→saw"),
    TestCase("She done her homework", "She did her homework", "grammar", "done→did"),
    TestCase("He has went home", "He has gone home", "grammar", "went→gone"),
    TestCase("I should of done it", "I should have done it", "grammar", "of→have"),
    TestCase("I could of been there", "I could have been there", "grammar", "of→have"),

    # -------------------------------------------------------------------------
    # GRAMMAR: Pronoun errors
    # -------------------------------------------------------------------------
    TestCase("Me and him went to school", "He and I went to school", "grammar", "pronoun order"),
    TestCase("Her and me are friends", "She and I are friends", "grammar", "pronoun case"),
    TestCase("Give it to John and I", "Give it to John and me", "grammar", "I→me"),

    # -------------------------------------------------------------------------
    # GRAMMAR: Article errors
    # -------------------------------------------------------------------------
    TestCase("I saw a elephant", "I saw an elephant", "grammar", "a→an"),
    TestCase("She is an doctor", "She is a doctor", "grammar", "an→a"),
    TestCase("I need an new computer", "I need a new computer", "grammar", "an→a"),

    # -------------------------------------------------------------------------
    # CORRECT SENTENCES (should not change)
    # -------------------------------------------------------------------------
    TestCase("I went to the store", "I went to the store", "correct", "no change needed"),
    TestCase("She is working hard", "She is working hard", "correct", "no change needed"),
    TestCase("The weather is nice", "The weather is nice", "correct", "no change needed"),
    TestCase("They're going to their house over there", "They're going to their house over there", "correct", "all correct"),
    TestCase("I know what you mean", "I know what you mean", "correct", "no change needed"),
    TestCase("It's clear that its tail is wagging", "It's clear that its tail is wagging", "correct", "both its forms correct"),
]


# =============================================================================
# MODEL WRAPPERS
# =============================================================================

class ModelWrapper:
    """Base class for model wrappers."""
    name: str = "base"

    def load(self):
        """Load the model."""
        raise NotImplementedError

    def correct(self, text: str) -> str:
        """Correct the input text."""
        raise NotImplementedError

    def cleanup(self):
        """Clean up resources."""
        pass


class CTranslate2Model(ModelWrapper):
    """Wrapper for CTranslate2 T5 models."""

    def __init__(self, name: str, model_path: str, tokenizer_name: str, prefix: str = ""):
        self.name = name
        self.model_path = model_path
        self.tokenizer_name = tokenizer_name
        self.prefix = prefix
        self.translator = None
        self.tokenizer = None

    def load(self):
        import ctranslate2
        import transformers
        self.translator = ctranslate2.Translator(self.model_path, compute_type="int8")
        self.tokenizer = transformers.AutoTokenizer.from_pretrained(self.tokenizer_name)

    def correct(self, text: str) -> str:
        input_text = f"{self.prefix}{text}" if self.prefix else text
        input_tokens = self.tokenizer.convert_ids_to_tokens(self.tokenizer.encode(input_text))
        result = self.translator.translate_batch([input_tokens])
        output_tokens = result[0].hypotheses[0]
        return self.tokenizer.decode(
            self.tokenizer.convert_tokens_to_ids(output_tokens),
            skip_special_tokens=True
        )


class BertMLMModel(ModelWrapper):
    """Wrapper for BERT-style masked language models for homophone scoring."""

    def __init__(self, name: str, model_name: str, homophones: dict):
        self.name = name
        self.model_name = model_name
        self.homophones = homophones  # word -> [alternatives]
        self.model = None
        self.tokenizer = None

    def load(self):
        from transformers import AutoModelForMaskedLM, AutoTokenizer
        import torch
        self.tokenizer = AutoTokenizer.from_pretrained(self.model_name)
        self.model = AutoModelForMaskedLM.from_pretrained(self.model_name)
        self.model.eval()

    def correct(self, text: str) -> str:
        import torch
        words = text.split()
        result_words = []

        for i, word in enumerate(words):
            word_lower = word.lower().rstrip(".,!?")
            if word_lower in self.homophones:
                # Create masked sentence
                masked_words = words.copy()
                masked_words[i] = self.tokenizer.mask_token
                masked_text = " ".join(masked_words)

                # Get predictions
                inputs = self.tokenizer(masked_text, return_tensors="pt")
                mask_idx = (inputs.input_ids == self.tokenizer.mask_token_id).nonzero(as_tuple=True)[1]

                with torch.no_grad():
                    outputs = self.model(**inputs)
                    logits = outputs.logits[0, mask_idx, :]

                # Score alternatives
                alternatives = self.homophones[word_lower]
                best_word = word
                best_score = float('-inf')

                for alt in alternatives:
                    alt_id = self.tokenizer.convert_tokens_to_ids(alt)
                    if alt_id != self.tokenizer.unk_token_id:
                        score = logits[0, alt_id].item()
                        if score > best_score:
                            best_score = score
                            best_word = alt

                # Preserve capitalization
                if word[0].isupper():
                    best_word = best_word.capitalize()
                result_words.append(best_word)
            else:
                result_words.append(word)

        return " ".join(result_words)


# =============================================================================
# EVALUATION
# =============================================================================

def normalize_text(text: str) -> str:
    """Normalize text for comparison."""
    return text.lower().strip().rstrip(".")

def evaluate_model(model: ModelWrapper, test_cases: list[TestCase], warmup: int = 3) -> dict:
    """Evaluate a model on the test set."""
    print(f"\nEvaluating: {model.name}")
    print("-" * 50)

    # Warmup
    for _ in range(warmup):
        model.correct("This is a warmup sentence.")

    results = {
        "name": model.name,
        "total": len(test_cases),
        "correct": 0,
        "by_category": {},
        "times": [],
        "errors": [],
    }

    for tc in test_cases:
        t0 = time.perf_counter()
        try:
            output = model.correct(tc.input)
        except Exception as e:
            output = f"ERROR: {e}"
        elapsed = (time.perf_counter() - t0) * 1000
        results["times"].append(elapsed)

        # Check correctness
        is_correct = normalize_text(output) == normalize_text(tc.expected)
        if is_correct:
            results["correct"] += 1
        else:
            results["errors"].append({
                "input": tc.input,
                "expected": tc.expected,
                "got": output,
                "category": tc.category,
            })

        # Track by category
        if tc.category not in results["by_category"]:
            results["by_category"][tc.category] = {"total": 0, "correct": 0}
        results["by_category"][tc.category]["total"] += 1
        if is_correct:
            results["by_category"][tc.category]["correct"] += 1

    # Calculate stats
    results["accuracy"] = results["correct"] / results["total"]
    results["latency_mean"] = statistics.mean(results["times"])
    results["latency_median"] = statistics.median(results["times"])
    results["latency_min"] = min(results["times"])
    results["latency_max"] = max(results["times"])

    return results


def print_results(results: dict):
    """Print evaluation results."""
    print(f"\n{'='*60}")
    print(f"Model: {results['name']}")
    print(f"{'='*60}")
    print(f"Overall: {results['correct']}/{results['total']} ({results['accuracy']*100:.1f}%)")
    print(f"Latency: {results['latency_median']:.1f}ms median, {results['latency_mean']:.1f}ms mean")
    print(f"         {results['latency_min']:.1f}ms min, {results['latency_max']:.1f}ms max")
    print()
    print("By Category:")
    for cat, stats in sorted(results["by_category"].items()):
        pct = stats["correct"] / stats["total"] * 100
        print(f"  {cat:12}: {stats['correct']:2}/{stats['total']:2} ({pct:5.1f}%)")

    if results["errors"]:
        print(f"\nErrors ({len(results['errors'])}):")
        for err in results["errors"][:10]:  # Show first 10
            print(f"  [{err['category']}] {err['input']}")
            print(f"    Expected: {err['expected']}")
            print(f"    Got:      {err['got']}")


def print_comparison_matrix(all_results: list[dict]):
    """Print a comparison matrix of all models."""
    print("\n" + "="*80)
    print("COMPARISON MATRIX")
    print("="*80)

    # Header
    print(f"\n{'Model':<30} {'Accuracy':>10} {'Homophone':>10} {'Grammar':>10} {'Latency':>10}")
    print("-"*80)

    for r in all_results:
        homo_stats = r["by_category"].get("homophone", {"correct": 0, "total": 0})
        gram_stats = r["by_category"].get("grammar", {"correct": 0, "total": 0})

        homo_pct = homo_stats["correct"] / homo_stats["total"] * 100 if homo_stats["total"] > 0 else 0
        gram_pct = gram_stats["correct"] / gram_stats["total"] * 100 if gram_stats["total"] > 0 else 0

        print(f"{r['name']:<30} {r['accuracy']*100:>9.1f}% {homo_pct:>9.1f}% {gram_pct:>9.1f}% {r['latency_median']:>8.1f}ms")


# =============================================================================
# MAIN
# =============================================================================

def main():
    print("GEC Model Comparison Framework")
    print("="*60)
    print(f"Test cases: {len(TEST_CASES)}")

    # Count by category
    categories = {}
    for tc in TEST_CASES:
        categories[tc.category] = categories.get(tc.category, 0) + 1
    for cat, count in sorted(categories.items()):
        print(f"  {cat}: {count}")

    # Define homophone groups for BERT MLM models
    HOMOPHONES = {
        "their": ["their", "there", "they're"],
        "there": ["their", "there", "they're"],
        "they're": ["their", "there", "they're"],
        "your": ["your", "you're"],
        "you're": ["your", "you're"],
        "its": ["its", "it's"],
        "it's": ["its", "it's"],
        "to": ["to", "too", "two"],
        "too": ["to", "too", "two"],
        "two": ["to", "too", "two"],
        "know": ["know", "no"],
        "no": ["know", "no"],
        "here": ["here", "hear"],
        "hear": ["here", "hear"],
        "write": ["write", "right"],
        "right": ["write", "right"],
        "weather": ["weather", "whether"],
        "whether": ["weather", "whether"],
        "through": ["through", "threw"],
        "threw": ["through", "threw"],
        "hole": ["hole", "whole"],
        "whole": ["hole", "whole"],
        "by": ["by", "buy", "bye"],
        "buy": ["by", "buy", "bye"],
        "bye": ["by", "buy", "bye"],
        "were": ["were", "where", "we're"],
        "where": ["were", "where", "we're"],
        "we're": ["were", "where", "we're"],
        "affect": ["affect", "effect"],
        "effect": ["affect", "effect"],
        "accept": ["accept", "except"],
        "except": ["accept", "except"],
    }

    # Define models to test
    models_dir = Path("/home/john/src/talkie/models/gec")

    models = []

    # CTranslate2 T5 models (already converted)
    if (models_dir / "t5-efficient-tiny-ct2").exists():
        models.append(CTranslate2Model(
            "t5-efficient-tiny",
            str(models_dir / "t5-efficient-tiny-ct2"),
            "visheratin/t5-efficient-tiny-grammar-correction"
        ))

    if (models_dir / "t5-efficient-mini-ct2").exists():
        models.append(CTranslate2Model(
            "t5-efficient-mini",
            str(models_dir / "t5-efficient-mini-ct2"),
            "visheratin/t5-efficient-mini-grammar-correction"
        ))

    if (models_dir / "t5-base-grammar-ct2").exists():
        models.append(CTranslate2Model(
            "t5-base-grammar",
            str(models_dir / "t5-base-grammar-ct2"),
            "vennify/t5-base-grammar-correction",
            prefix="grammar: "
        ))

    # Add BERT MLM models for homophone scoring
    try:
        models.append(BertMLMModel(
            "distilbert-mlm",
            "distilbert-base-uncased",
            HOMOPHONES
        ))
    except Exception as e:
        print(f"Warning: Could not add distilbert-mlm: {e}")

    # Add ELECTRA-Small (discriminative, more efficient)
    try:
        models.append(BertMLMModel(
            "electra-small-mlm",
            "google/electra-small-generator",
            HOMOPHONES
        ))
    except Exception as e:
        print(f"Warning: Could not add electra-small: {e}")

    # Add BERT-base for comparison
    try:
        models.append(BertMLMModel(
            "bert-base-mlm",
            "bert-base-uncased",
            HOMOPHONES
        ))
    except Exception as e:
        print(f"Warning: Could not add bert-base: {e}")

    # Load and evaluate each model
    all_results = []

    for model in models:
        try:
            print(f"\nLoading {model.name}...")
            model.load()
            results = evaluate_model(model, TEST_CASES)
            print_results(results)
            all_results.append(results)
            model.cleanup()
        except Exception as e:
            print(f"Error with {model.name}: {e}")
            import traceback
            traceback.print_exc()

    # Print comparison matrix
    if len(all_results) > 1:
        print_comparison_matrix(all_results)

    # Save results to JSON
    output_file = Path(__file__).parent / "gec_comparison_results.json"
    with open(output_file, "w") as f:
        # Remove non-serializable items
        for r in all_results:
            r.pop("times", None)
        json.dump(all_results, f, indent=2)
    print(f"\nResults saved to {output_file}")


if __name__ == "__main__":
    main()
