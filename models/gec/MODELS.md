# GEC Model Setup Guide

This document describes how to download and convert all models required for the Grammar Error Correction pipeline.

## Model Overview

| Stage | Model | Source | Format | Size |
|-------|-------|--------|--------|------|
| 1. Homophone | ELECTRA-Small Generator | HuggingFace | ONNX | ~50 MB |
| 2. Punct/Caps | DistilBERT Punct-Cap | HuggingFace | ONNX | ~250 MB |
| 3. Grammar | T5-efficient-tiny | HuggingFace | CTranslate2 | ~16 MB |

## Prerequisites

```bash
# Python virtual environment with required tools
python3 -m venv ~/venv/gec-convert
source ~/venv/gec-convert/bin/activate
pip install transformers optimum onnx onnxruntime ctranslate2 sentencepiece
```

---

## Stage 1: Homophone Model (ELECTRA-Small)

**Source:** `google/electra-small-generator`
**Purpose:** Masked language model for scoring homophone alternatives
**Device:** NPU (OpenVINO)

### Download and Convert

```bash
source ~/venv/gec-convert/bin/activate
cd ~/src/talkie/models/gec

# Convert to ONNX with Optimum
optimum-cli export onnx \
  --model google/electra-small-generator \
  --task fill-mask \
  electra-small-generator-onnx/

# Copy the ONNX file to expected location
cp electra-small-generator-onnx/model.onnx electra-small-generator.onnx
```

### Verify

```bash
ls -lh electra-small-generator.onnx
# Should be ~50 MB
```

---

## Stage 2: Punctuation/Capitalization Model (DistilBERT)

**Source:** `oliverguhr/fullstop-punctuation-multilang-large` (or similar)
**Purpose:** Token classification for punctuation and capitalization
**Device:** NPU (OpenVINO)

### Download and Convert

```bash
source ~/venv/gec-convert/bin/activate
cd ~/src/talkie/models/gec

# Convert to ONNX with Optimum
optimum-cli export onnx \
  --model oliverguhr/fullstop-punctuation-multilang-large \
  --task token-classification \
  distilbert-punct-cap-onnx/

# Copy to expected location
cp distilbert-punct-cap-onnx/model.onnx distilbert-punct-cap.onnx
```

### Alternative: Train Custom Model

If using a custom punctuation model, export from PyTorch:

```python
import torch
from transformers import AutoModelForTokenClassification, AutoTokenizer

model = AutoModelForTokenClassification.from_pretrained("your-model")
tokenizer = AutoTokenizer.from_pretrained("your-model")

dummy_input = tokenizer("test input", return_tensors="pt")
torch.onnx.export(
    model,
    (dummy_input["input_ids"], dummy_input["attention_mask"]),
    "distilbert-punct-cap.onnx",
    input_names=["input_ids", "attention_mask"],
    output_names=["logits"],
    dynamic_axes={"input_ids": {0: "batch", 1: "seq"},
                  "attention_mask": {0: "batch", 1: "seq"},
                  "logits": {0: "batch", 1: "seq"}}
)
```

---

## Stage 3: Grammar Model (T5-efficient-tiny)

**Source:** `visheratin/t5-efficient-tiny-grammar-correction`
**Purpose:** Seq2seq grammar correction (subject-verb agreement, tense, articles)
**Device:** CPU (CTranslate2)

### Why CTranslate2?

- 2.2x faster than ONNX Runtime for seq2seq models
- Excellent INT8 quantization on Intel CPUs
- T5 decoder has dynamic shapes incompatible with NPU

### Download and Convert

```bash
source ~/venv/gec-convert/bin/activate
cd ~/src/talkie/models/gec

# Convert HuggingFace model to CTranslate2 format with INT8 quantization
ct2-transformers-converter \
  --model visheratin/t5-efficient-tiny-grammar-correction \
  --output_dir t5-grammar-ct2 \
  --quantization int8
```

### Add SentencePiece Tokenizer

The T5 model requires a SentencePiece tokenizer. Copy from the base T5 model:

```bash
# Download spiece.model from t5-small (same tokenizer)
cd t5-grammar-ct2

# Option 1: From HuggingFace cache (if you have t5-small downloaded)
cp ~/.cache/huggingface/hub/models--t5-small/blobs/<hash> spiece.model

# Option 2: Download directly
python3 -c "
from transformers import T5Tokenizer
tok = T5Tokenizer.from_pretrained('t5-small')
tok.save_pretrained('.')
"
# This creates spiece.model in current directory
```

### Verify Model Files

```bash
ls -lh t5-grammar-ct2/
# Expected files:
#   config.json          ~226 bytes
#   model.bin            ~15.8 MB (INT8 quantized weights)
#   shared_vocabulary.json ~537 KB
#   spiece.model         ~792 KB (SentencePiece tokenizer)
```

### Test Grammar Model

```bash
cd ~/src/talkie
LD_LIBRARY_PATH=$HOME/.local/lib:$HOME/.local/lib64 tclsh8.6 <<'EOF'
lappend auto_path src/gec/lib
package require ct2
set model [ct2::load_model -path models/gec/t5-grammar-ct2]
puts [$model correct "I has going to store"]
# Expected: "I have been going to the store."
$model close
EOF
```

---

## Vocabulary File

The homophone and punctuation models share a WordPiece vocabulary:

**Location:** `src/gec/vocab.txt`
**Source:** BERT base uncased vocabulary (30,522 tokens)

```bash
# Download if missing
wget https://huggingface.co/bert-base-uncased/raw/main/vocab.txt \
  -O ~/src/talkie/src/gec/vocab.txt
```

---

## Build Dependencies

The GEC pipeline requires native libraries built from source:

### CTranslate2 (for T5 grammar model)

```bash
cd ~/pkg
git clone https://github.com/OpenNMT/CTranslate2.git
cd CTranslate2
git submodule update --init --recursive
mkdir build && cd build
cmake .. \
  -DWITH_MKL=OFF \
  -DWITH_OPENBLAS=ON \
  -DOPENBLAS_INCLUDE_DIR=/usr/include/openblas \
  -DOPENMP_RUNTIME=COMP \
  -DCMAKE_INSTALL_PREFIX=$HOME/.local
make -j$(nproc)
make install
```

### SentencePiece (tokenizer for T5)

```bash
cd ~/pkg
git clone https://github.com/google/sentencepiece.git
cd sentencepiece
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/.local
make -j$(nproc)
make install
```

### OpenVINO (for NPU inference)

See `tools/NPU-BUILD-GUIDE.md` for building OpenVINO from source.

### Intel NPU Driver

```bash
cd ~/pkg
git clone https://github.com/intel/linux-npu-driver.git
cd linux-npu-driver
# Follow build instructions in README
```

---

## Directory Structure

After setup, the models directory should contain:

```
models/gec/
├── MODELS.md                      # This file
├── electra-small-generator.onnx   # Stage 1: Homophone (NPU)
├── distilbert-punct-cap.onnx      # Stage 2: Punct/Caps (NPU)
└── t5-grammar-ct2/                # Stage 3: Grammar (CPU)
    ├── config.json
    ├── model.bin
    ├── shared_vocabulary.json
    ├── spiece.model
    ├── special_tokens_map.json
    ├── tokenizer.json
    └── tokenizer_config.json
```

---

## Troubleshooting

### "INT8 compute type not supported"

CTranslate2 was built without INT8 support. Either:
1. Rebuild with OpenBLAS: `cmake .. -DWITH_OPENBLAS=ON`
2. Or use AUTO compute type (edit `src/gec/ct2.tcl` line ~199)

### "Failed to load tokenizer: spiece.model not found"

Copy the SentencePiece model file:
```bash
cp ~/.cache/huggingface/hub/models--t5-small/blobs/* models/gec/t5-grammar-ct2/spiece.model
```

### NPU not detected

Ensure library paths are set (see `src/gec/LIBRARIES.md`):
```bash
export LD_LIBRARY_PATH=$HOME/pkg/linux-npu-driver/build/lib:$HOME/pkg/openvino-src/bin/intel64/Release:$HOME/.local/lib:$HOME/.local/lib64
```

---

## Model Sources

| Model | HuggingFace URL |
|-------|-----------------|
| ELECTRA-Small | https://huggingface.co/google/electra-small-generator |
| T5-efficient-tiny Grammar | https://huggingface.co/visheratin/t5-efficient-tiny-grammar-correction |
| DistilBERT Punct | https://huggingface.co/oliverguhr/fullstop-punctuation-multilang-large |
| BERT Vocabulary | https://huggingface.co/bert-base-uncased |
