# GECToR Training Pipeline for Talkie

Training a small, non-hallucinating grammar correction model for NPU deployment.

## Overview

| Property | Target |
|----------|--------|
| Architecture | GECToR (tag-based) |
| Encoder | ELECTRA-small (14M params) |
| Training Data | C4_200M streamed subset (2M examples, CC BY 4.0) |
| Output Size | ~50-60 MB |
| Target Latency | 10-15ms on NPU |
| Hallucination Risk | None (tag-based) |

## Why GECToR?

GECToR uses ~5000 predefined correction tags instead of generating text:
- `$KEEP` - keep token unchanged
- `$DELETE` - remove token
- `$REPLACE_have` - replace with "have"
- `$APPEND_the` - append "the" after token

**Cannot hallucinate** - only applies operations from fixed vocabulary.

---

## Phase 1: Environment Setup

### 1.1 Create Training Virtual Environment

```bash
cd ~/src/talkie
python3 -m venv venv/gector
source venv/gector/bin/activate
```

### 1.2 Clone GECToR Repository

```bash
cd ~/pkg
git clone https://github.com/gotutiyan/gector.git gector-train
cd gector-train
```

Using the [gotutiyan/gector](https://github.com/gotutiyan/gector) unofficial PyTorch implementation (modern dependencies, Python 3.11 compatible).

### 1.3 Install Dependencies

```bash
pip install torch transformers datasets
pip install -e .
```

### 1.4 Verify ELECTRA-small Support

Check if ELECTRA is supported. If not, may need to add it:

```python
from transformers import AutoModel
model = AutoModel.from_pretrained("google/electra-small-discriminator")
print(f"Parameters: {sum(p.numel() for p in model.parameters()):,}")
# Expected: ~13.5M parameters
```

---

## Phase 2: Stream and Filter C4_200M Dataset

### 2.1 Dataset Information

| Attribute | Value |
|-----------|-------|
| Source | [HuggingFace liweili/c4_200m](https://huggingface.co/datasets/liweili/c4_200m) |
| License | CC BY 4.0 (commercial OK) |
| Full Size | 185 million sentence pairs (~750 GB source) |
| Our Target | 1-5 million filtered pairs (~500 MB - 2 GB) |
| Format | Streaming with filter + shuffle |

### 2.2 Why Streaming?

The full C4_200M requires downloading ~750 GB of C4 corpus. Instead, we:
1. **Stream** data on-demand (no full download)
2. **Filter** for relevant grammar error types
3. **Shuffle** with buffer for randomization
4. **Save** only what we need (1-5M examples)

### 2.3 Install Dependencies

```bash
pip install datasets tqdm
```

### 2.4 Create Data Collection Script

Create `scripts/collect_gec_data.py`:

```python
#!/usr/bin/env python3
"""
Stream, filter, and collect GEC training data from C4_200M.
Outputs randomized, filtered subset focused on speech-to-text errors.
"""

import random
from datasets import load_dataset
from tqdm import tqdm

# Configuration
TARGET_SAMPLES = 2_000_000  # 2M examples
SHUFFLE_BUFFER = 500_000    # Randomization buffer
OUTPUT_FILE = "gec_train_2M.tsv"
SEED = 42

# Error patterns relevant to speech-to-text output
# These are the grammar errors we actually see from Vosk/Sherpa
RELEVANT_PATTERNS = [
    # Subject-verb agreement (high priority)
    ("i has ", "i have "),
    ("he have ", "he has "),
    ("she have ", "she has "),
    ("it have ", "it has "),
    ("they was ", "they were "),
    ("we was ", "we were "),
    ("there is many", "there are many"),
    ("there's many", "there are many"),

    # Verb tense errors
    ("i seen ", "i saw "),
    ("i done ", "i did "),
    ("he seen ", "he saw "),
    ("she done ", "she did "),
    ("i been ", "i have been "),
    ("could of ", "could have "),
    ("would of ", "would have "),
    ("should of ", "should have "),

    # Article errors (common in fast speech)
    (" a apple", " an apple"),
    (" a hour", " an hour"),
    (" a honest", " an honest"),
    (" an book", " a book"),
    (" an car", " a car"),

    # Missing articles
    ("go to store", "go to the store"),
    ("at store", "at the store"),
    ("in morning", "in the morning"),

    # Contractions
    ("dont ", "don't "),
    ("cant ", "can't "),
    ("wont ", "won't "),
    ("didnt ", "didn't "),
    ("doesnt ", "doesn't "),
    ("isnt ", "isn't "),
    ("arent ", "aren't "),
    ("wasnt ", "wasn't "),
    ("werent ", "weren't "),
    ("ive ", "i've "),
    ("youve ", "you've "),
    ("theyve ", "they've "),
    ("youre ", "you're "),
    ("theyre ", "they're "),
    ("were ", "we're "),  # careful - also past tense of "be"
    ("hes ", "he's "),
    ("shes ", "she's "),
    ("its a ", "it's a "),  # possessive vs contraction

    # Double negatives
    ("don't know nothing", "don't know anything"),
    ("can't find nothing", "can't find anything"),
]

def is_relevant(example):
    """Check if example contains error patterns we care about."""
    source = example.get("source", example.get("input", "")).lower()
    target = example.get("target", example.get("output", "")).lower()

    # Must have actual difference
    if source == target:
        return False

    # Check for relevant patterns
    for error_pattern, correction_pattern in RELEVANT_PATTERNS:
        if error_pattern in source or correction_pattern in target:
            return True

    # Also accept any example where source != target and length is similar
    # (likely a grammar fix, not a major rewrite)
    len_ratio = len(target) / max(len(source), 1)
    if 0.8 <= len_ratio <= 1.2:
        # Small edit, probably grammar
        return True

    return False

def collect_data():
    """Stream, filter, shuffle, and save training data."""
    print(f"Loading C4_200M dataset (streaming mode)...")

    # Load with streaming - no full download
    ds = load_dataset("liweili/c4_200m", split="train", streaming=True)

    # Shuffle with buffer for randomization
    print(f"Shuffling with buffer size {SHUFFLE_BUFFER:,}...")
    ds = ds.shuffle(buffer_size=SHUFFLE_BUFFER, seed=SEED)

    # Collect filtered samples
    samples = []
    seen = 0

    print(f"Collecting {TARGET_SAMPLES:,} relevant examples...")

    with tqdm(total=TARGET_SAMPLES, desc="Collecting") as pbar:
        for example in ds:
            seen += 1

            if is_relevant(example):
                source = example.get("source", example.get("input", ""))
                target = example.get("target", example.get("output", ""))

                # Skip if empty
                if not source.strip() or not target.strip():
                    continue

                samples.append((source.strip(), target.strip()))
                pbar.update(1)

                if len(samples) >= TARGET_SAMPLES:
                    break

            # Progress update every 100K
            if seen % 100000 == 0:
                pbar.set_postfix({"seen": f"{seen:,}", "rate": f"{len(samples)/seen:.1%}"})

    print(f"\nScanned {seen:,} examples, collected {len(samples):,}")
    print(f"Filter rate: {len(samples)/seen:.1%}")

    # Final shuffle
    print("Final shuffle...")
    random.seed(SEED)
    random.shuffle(samples)

    # Save to TSV
    print(f"Saving to {OUTPUT_FILE}...")
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        for source, target in samples:
            # Escape tabs and newlines
            source = source.replace("\t", " ").replace("\n", " ")
            target = target.replace("\t", " ").replace("\n", " ")
            f.write(f"{source}\t{target}\n")

    print(f"Done! Saved {len(samples):,} examples to {OUTPUT_FILE}")

    # Print statistics
    print("\nSample examples:")
    for i in range(min(5, len(samples))):
        print(f"  {samples[i][0][:60]}...")
        print(f"  → {samples[i][1][:60]}...")
        print()

if __name__ == "__main__":
    collect_data()
```

### 2.5 Run Data Collection

```bash
cd ~/data/gec
python ~/src/talkie/scripts/collect_gec_data.py
```

**Expected output:**
- Time: 1-4 hours (depending on filter rate)
- Output: `gec_train_2M.tsv` (~500 MB - 1 GB)
- Format: `source<TAB>target` pairs

### 2.6 Verify Data Quality

```bash
# Check file size
ls -lh gec_train_2M.tsv

# Count lines
wc -l gec_train_2M.tsv

# View samples
head -20 gec_train_2M.tsv | column -t -s $'\t'

# Check for pattern distribution
grep -c "have" gec_train_2M.tsv
grep -c "don't" gec_train_2M.tsv
```

### 2.7 Stratified Sampling (Optional)

For balanced error types, use stratified collection:

```python
# Collect equal samples per error category
error_buckets = {
    "subject_verb": [],    # 500K
    "verb_tense": [],      # 500K
    "articles": [],        # 500K
    "contractions": [],    # 500K
}
target_per_bucket = 500_000

# ... filter into buckets instead of single list
```

### 2.8 Data Size Options

| Size | Examples | Disk | Training Time | Quality |
|------|----------|------|---------------|---------|
| Small | 500K | ~250 MB | 2-4 hours | Good baseline |
| Medium | 2M | ~1 GB | 8-12 hours | Recommended |
| Large | 5M | ~2.5 GB | 1-2 days | Best quality |

Start with **2M examples** - good balance of quality and training time.

---

## Phase 3: Preprocess Data for GECToR

### 3.1 Convert Sentence Pairs to Tagged Format

GECToR needs token-level tags, not sentence pairs:

```
Input:  I has going to store
Tags:   $KEEP $REPLACE_have $REPLACE_been $KEEP $APPEND_the $KEEP
```

### 3.2 Split TSV into Source and Target Files

```bash
cd ~/data/gec

# Split the TSV from Phase 2 into separate files
cut -f1 gec_train_2M.tsv > source.txt
cut -f2 gec_train_2M.tsv > target.txt

# Verify line counts match
wc -l source.txt target.txt
```

### 3.3 Run GECToR Preprocessing Script

```bash
cd ~/pkg/gector-train

# Generate tagged training data
# This aligns source/target and computes edit operations
python utils/preprocess_data.py \
    -s ~/data/gec/source.txt \
    -t ~/data/gec/target.txt \
    -o ~/data/gec/train_tagged.txt
```

**Expected time:** 30-60 minutes for 2M examples

### 3.4 Verify Tagged Output

```bash
# Check output format
head -5 ~/data/gec/train_tagged.txt

# Expected format (space-separated tokens with tags):
# I $KEEP has $REPLACE_have going $REPLACE_been to $KEEP store $APPEND_the
```

### 3.5 Create Train/Dev/Test Split

```bash
cd ~/data/gec

# Data is already shuffled from collection, just split
# 90% train, 5% dev, 5% test
total=$(wc -l < train_tagged.txt)
train_size=$((total * 90 / 100))
dev_size=$((total * 5 / 100))

head -n $train_size train_tagged.txt > train.txt
tail -n +$((train_size + 1)) train_tagged.txt | head -n $dev_size > dev.txt
tail -n $dev_size train_tagged.txt > test.txt

# Verify splits
wc -l train.txt dev.txt test.txt
```

**Expected output for 2M examples:**
- train.txt: 1,800,000 lines
- dev.txt: 100,000 lines
- test.txt: 100,000 lines

---

## Phase 4: Train GECToR Model

### 4.1 Training Configuration

Create `config/electra_small.yaml`:

```yaml
model:
  encoder: google/electra-small-discriminator
  num_labels: 5000  # tag vocabulary size

training:
  batch_size: 256        # Stage I
  learning_rate: 1e-5
  epochs: 20
  early_stopping: 3      # epochs without improvement
  freeze_encoder: 2      # freeze for first N epochs

data:
  train: train.txt
  dev: dev.txt
  max_len: 128
```

### 4.2 Stage I: Pre-training on Synthetic Data

```bash
python train.py \
    --model_id google/electra-small-discriminator \
    --train_path train.txt \
    --dev_path dev.txt \
    --batch_size 256 \
    --epochs 20 \
    --lr 1e-5 \
    --cold_epochs 2 \
    --output_dir checkpoints/electra-small-stage1
```

**Expected time: 1-2 days on RTX 4070**

### 4.3 Stage II: Fine-tuning (Optional)

If using additional real error data (JFLEG for evaluation only):

```bash
python train.py \
    --model_id checkpoints/electra-small-stage1 \
    --train_path finetune_train.txt \
    --dev_path finetune_dev.txt \
    --batch_size 128 \
    --epochs 3 \
    --lr 1e-6 \
    --output_dir checkpoints/electra-small-stage2
```

### 4.4 Monitor Training

```bash
# Watch GPU usage
watch -n 1 nvidia-smi

# Monitor training logs
tail -f checkpoints/electra-small-stage1/training.log
```

---

## Phase 5: Evaluate Model

### 5.1 Run Evaluation

```bash
python predict.py \
    --model_id checkpoints/electra-small-stage1 \
    --input_path test_source.txt \
    --output_path predictions.txt
```

### 5.2 Calculate Metrics

Using ERRANT for GEC evaluation:

```bash
pip install errant

# Generate error annotations
errant_parallel -orig test_source.txt -cor test_target.txt -out test.m2
errant_parallel -orig test_source.txt -cor predictions.txt -out pred.m2

# Compare
errant_compare -hyp pred.m2 -ref test.m2
```

### 5.3 Expected Performance

| Model | F0.5 (BEA-2019) | Size |
|-------|-----------------|------|
| GECToR-BERT-base | 65.3 | 440 MB |
| GECToR-ELECTRA-small (target) | ~58-62 | 50 MB |

---

## Phase 6: Export to OpenVINO

### 6.1 Export to ONNX

```python
import torch
from gector import GECToR

model = GECToR.from_pretrained("checkpoints/electra-small-stage1")
model.eval()

dummy_input = {
    "input_ids": torch.zeros(1, 128, dtype=torch.long),
    "attention_mask": torch.ones(1, 128, dtype=torch.long),
}

torch.onnx.export(
    model,
    (dummy_input["input_ids"], dummy_input["attention_mask"]),
    "gector-electra-small.onnx",
    input_names=["input_ids", "attention_mask"],
    output_names=["logits"],
    dynamic_axes={
        "input_ids": {0: "batch", 1: "seq"},
        "attention_mask": {0: "batch", 1: "seq"},
        "logits": {0: "batch", 1: "seq"},
    },
    opset_version=14,
)
```

### 6.2 Convert to OpenVINO IR

```bash
# Activate OpenVINO environment
source ~/intel/openvino/setupvars.sh

# Convert ONNX to OpenVINO IR
ovc gector-electra-small.onnx \
    --output_model gector-electra-small \
    --compress_to_fp16
```

### 6.3 Quantize to INT8 (Optional)

```python
from openvino.tools import mo
from openvino.runtime import Core
import nncf

# Post-training quantization
quantized_model = nncf.quantize(model, calibration_dataset)
```

---

## Phase 7: Integrate with Talkie

### 7.1 Copy Model Files

```bash
mkdir -p ~/src/talkie/models/gec/gector-electra-small
cp gector-electra-small.xml ~/src/talkie/models/gec/gector-electra-small/
cp gector-electra-small.bin ~/src/talkie/models/gec/gector-electra-small/
cp vocab.txt ~/src/talkie/models/gec/gector-electra-small/
cp tags.txt ~/src/talkie/models/gec/gector-electra-small/
```

### 7.2 Create Tcl Wrapper

Create `src/gec/gector.tcl` following the pattern of existing `gec.tcl`:

```tcl
package require gec

namespace eval gector {
    variable model ""
    variable request ""
    variable initialized 0
    variable tag_vocab {}
}

proc gector::init {args} {
    # Load OpenVINO model
    # Load tag vocabulary
    # Create inference request
}

proc gector::correct {text} {
    # Tokenize input
    # Run inference
    # Decode tags to corrections
    # Apply corrections
    # Return corrected text
}
```

### 7.3 Update Pipeline

Modify `src/gec/pipeline.tcl` to use gector instead of grammar.tcl:

```tcl
proc gec_pipeline::process {text} {
    # Stage 1: Homophones (ELECTRA MLM)
    set text [homophone::correct $text]

    # Stage 2: Punctuation/Caps (DistilBERT)
    set text [punctcap::restore $text]

    # Stage 3: Grammar (GECToR) - NEW
    if {$grammar_enabled} {
        set text [gector::correct $text]
    }

    return $text
}
```

---

## Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| GPU | RTX 3060 (12GB) | RTX 4070 (12GB) |
| RAM | 16 GB | 64 GB |
| Storage | 10 GB | 20 GB |
| Network | Broadband (streaming) | Fast broadband |
| Training Time | 12-24 hours | 8-12 hours |

**Note:** Streaming approach eliminates need for 750 GB storage.

---

## Estimated Timeline

| Phase | Duration |
|-------|----------|
| Environment setup | 1 hour |
| Stream & filter data (2M) | 2-4 hours |
| Preprocess to tags | 1-2 hours |
| Training Stage I | 8-12 hours |
| Evaluation | 1 hour |
| Export to OpenVINO | 1 hour |
| Integration | 2-4 hours |
| **Total** | **1-2 days** |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| ELECTRA-small not supported in GECToR | Add encoder support (minimal code change) |
| Training diverges | Use smaller learning rate, longer warmup |
| Model too large | Try BERT-Tiny (4.4M params) as encoder |
| Poor accuracy | Increase to 5M examples, adjust filter criteria |
| NPU inference issues | Fall back to CPU (still fast at this size) |
| Streaming too slow | Use larger buffer, run overnight |
| Filter rate too low | Relax pattern matching, accept more examples |
| HuggingFace rate limits | Use authentication token, retry with backoff |

---

## References

- [GECToR Paper](https://aclanthology.org/2020.bea-1.16/)
- [gotutiyan/gector](https://github.com/gotutiyan/gector) - Modern PyTorch implementation
- [C4_200M Dataset](https://github.com/google-research-datasets/C4_200M-synthetic-dataset-for-grammatical-error-correction)
- [OpenVINO Model Optimization](https://docs.openvino.ai/latest/openvino_docs_model_optimization_guide.html)
- [ERRANT Evaluation](https://github.com/chrisjbryant/errant)

---

## Next Steps

1. [ ] Set up training environment (venv, clone gector repo)
2. [ ] Verify ELECTRA-small works with GECToR codebase
3. [ ] Run data collection script (stream 2M filtered examples)
4. [ ] Preprocess to GECToR tagged format
5. [ ] Train GECToR-ELECTRA-small model
6. [ ] Evaluate on held-out test set
7. [ ] Export to ONNX → OpenVINO IR
8. [ ] Test inference latency on NPU
9. [ ] Integrate with Talkie GEC pipeline
10. [ ] A/B test against disabled grammar stage
