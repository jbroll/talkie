# AI Models for Speech Recognition Post-Processing

Research summary for using small AI models to improve Vosk speech recognition output.

## Current Approach: Bigrams/Trigrams

The POS service uses word bigrams and distinguishing trigrams extracted from the Vosk language model:

| Data | Size | Speed | Coverage |
|------|------|-------|----------|
| Word bigrams | 21 MB (932k entries) | <1ms | Co-occurrence patterns |
| Distinguishing trigrams | 3.8 MB (113k entries) | <1ms | Cases where 3-word context differs from 2-word |

**Limitations:**
- Only sees 2-3 word context
- Cannot handle novel phrases not in training data
- No semantic understanding

---

## AI Model Options

### 1. Masked Language Models (BERT-style)

**How it works:** Score word probabilities using full sentence context.

```
Input:  "I heard the [MASK] falling down"
Scores: wood=0.85, would=0.12, good=0.03
```

**Best candidates:**

| Model | Parameters | Size (INT8) | Speed (C/ONNX) | Quality |
|-------|------------|-------------|----------------|---------|
| DistilBERT | 66M | 66 MB | 10-30ms | 97% of BERT |
| ModernBERT | 130M | 130 MB | 15-40ms | State-of-art 2024 |
| RoBERTa-base | 125M | 125 MB | 20-50ms | Better than BERT |

**Pros:** Fast single-word scoring, bidirectional context
**Cons:** Only fixes one word at a time, no grammar correction

---

### 2. GECToR (Grammatical Error Correction)

**How it works:** Tag-based approach - assigns correction tags to each token in parallel.

```
Input:  "I has going to store"
Tags:   [KEEP, REPLACE_have, REPLACE_been, KEEP, APPEND_the, KEEP]
Output: "I have been going to the store"
```

**Architecture:**
- Transformer encoder (BERT/RoBERTa/XLNet) + two linear layers
- 5,000 correction tags covering common errors
- Non-autoregressive (all predictions in parallel)

**Performance:**

| Model | Size | Speed | Accuracy (BEA-2019) |
|-------|------|-------|---------------------|
| GECToR-BERT | ~420 MB | 10x faster than T5 | 65.3 F0.5 |
| GECToR-RoBERTa | ~500 MB | Similar | 68.2 F0.5 |
| GECToR-XLNet | ~1.3 GB | Slightly slower | 72.4 F0.5 |
| Ensemble | ~2 GB | 3x slower | 76.05 F0.5 |

**What it corrects:**
- Homophones (their/there/they're)
- Subject-verb agreement (I has → I have)
- Article errors (a apple → an apple)
- Verb tense/form
- Missing words
- Punctuation
- Capitalization

**Limitations:**
- Max 80 tokens per sentence
- English only (officially)
- Struggles with idioms, temporal context
- 2 iterations needed for dependent errors

---

### 3. Seq2Seq Models (T5, BART)

**How it works:** Generate corrected text token-by-token.

**Standard T5 Performance:**
- T5-small: 60M params, 240 MB, 100-300ms/sentence
- Better for complete rewrites
- 10x slower than GECToR

**Efficient T5 Variants (Updated Jan 2026):**

| Model | Parameters | Size (INT8) | Expected Latency | Notes |
|-------|------------|-------------|------------------|-------|
| t5-efficient-tiny | ~12M | ~12 MB | 20-60ms | Smallest viable |
| t5-efficient-mini | ~31M | ~31 MB | 30-80ms | Better quality |
| grammar-synthesis-small | 60M | ~60 MB | 50-150ms | JFLEG-trained |

**Pre-built ONNX Models Available:**
- `visheratin/t5-efficient-tiny-grammar-correction` - Ready for ONNX Runtime
- `visheratin/t5-efficient-mini-grammar-correction` - Better quality/speed tradeoff
- `onnx-community/t5-base-grammar-correction-ONNX` - Full T5-base in ONNX
- `Xenova/t5-base-grammar-correction` - Quantized for web/edge

The tiny/mini variants may be competitive with GECToR due to smaller size, despite autoregressive generation.

---

## Speed Comparison

| Approach | Latency | Notes |
|----------|---------|-------|
| Bigrams/trigrams | <1ms | Current implementation |
| DistilBERT (Python) | 100-300ms | HuggingFace transformers |
| DistilBERT (ONNX Python) | 30-80ms | ONNX Runtime bindings |
| DistilBERT (ONNX C, INT8) | 10-30ms | Native C, quantized |
| GECToR (Python) | 100-300ms | Per sentence |
| GECToR (ONNX C, INT8) | 20-50ms | Estimated |
| t5-efficient-tiny (CTranslate2, INT8) | 20-60ms | Needs benchmarking |
| t5-efficient-mini (CTranslate2, INT8) | 30-80ms | Needs benchmarking |

**Your hardware (Intel Core Ultra 7 155H):**
- Supports AVX2, VNNI instructions
- INT8 quantization gives 2-3x speedup
- Expected: 20-50ms for GECToR with ONNX Runtime
- CTranslate2 reported 2.2x faster than ONNX Runtime for T5 models

---

## C/C++ Integration Options

### CTranslate2 (Recommended for T5)

**Why CTranslate2:**
- Powers faster-whisper (already integrated in Talkie)
- 2.2x faster than ONNX Runtime for T5/seq2seq models
- Transformer-specific optimizations (layer fusion, batch reordering)
- Excellent INT8 quantization on Intel CPUs
- Installing faster-whisper brings both CTranslate2 AND ONNX Runtime

```cpp
#include "ctranslate2/translator.h"

auto translator = ctranslate2::Translator("./t5-grammar-ct2");
auto result = translator.translate_batch({tokens});
```

**Conversion from HuggingFace:**
```bash
ct2-transformers-converter \
  --model visheratin/t5-efficient-mini-grammar-correction \
  --output_dir ./t5-grammar-ct2 \
  --quantization int8
```

**Pros:**
- Best performance for seq2seq models
- Same backend as faster-whisper
- ~55 MB for INT8 T5-base (4x reduction)
- Process-based IPC matches existing POS service architecture

### ONNX Runtime

```c
// Pseudocode
OrtEnv* env = OrtCreateEnv(...);
OrtSession* session = OrtCreateSession(env, "gector.onnx", opts);
OrtRun(session, input_ids, output_tags);
```

**Pros:**
- Clean C API
- Excellent INT8/INT4 quantization
- Cross-platform
- Well documented
- Better for GECToR (encoder-only, tag-based)

**Tcl integration:** Create C extension or use FFI (`ffidl`)

### llama.cpp / ggml

- Better for generative models (GPT-style)
- No GEC-specific GGUF models available
- Less ideal for encoder-only models
- No existing Tcl bindings

### TorchScript / LibTorch

```cpp
auto module = torch::jit::load("gector.pt");
auto output = module.forward(inputs);
```

- Native C++ with PyTorch
- Tokenization handled separately

---

## Recommendation

### Two Viable Paths (Updated Jan 2026)

#### Option A: GECToR (Tag-based)
**Why:**
1. Fixes homophones AND grammar in one pass
2. 10x faster than standard seq2seq (T5-small)
3. Parallel inference (non-autoregressive)
4. Well-tested, production-ready (Grammarly uses it)
5. Can be quantized for faster CPU inference

**Challenges:**
- Old dependencies (AllenNLP 0.8.4, PyTorch 1.10)
- No pre-built ONNX models available
- Requires conversion work

#### Option B: T5-efficient-tiny/mini (Seq2Seq)
**Why:**
1. Pre-built ONNX models ready to use
2. CTranslate2 integration via faster-whisper (already in Talkie)
3. Much smaller than original T5 research suggested
4. Simple development path - same coprocess architecture as POS service

**Trade-offs:**
- Autoregressive generation (theoretically slower)
- May match GECToR speed due to 5-10x smaller size

### Recommended Implementation Path

**Phase 1: Install faster-whisper + benchmark tiny T5**
- `pip install faster-whisper` brings CTranslate2 + ONNX Runtime
- Convert `visheratin/t5-efficient-tiny-grammar-correction` to CTranslate2
- Benchmark actual latency on Intel Core Ultra 7

**Phase 2: Python coprocess service**
- Same architecture as POS service (stdin/stdout JSON)
- Load model once, process corrections on demand
- Target: <100ms per correction

**Phase 3: Evaluate and optimize**
- If tiny T5 meets latency targets, done
- If not, try GECToR with ONNX Runtime
- Consider C extension only if Python latency is unacceptable

---

## Comparison: Bigrams vs AI Models

| Aspect | Bigrams/Trigrams | GECToR | T5-efficient-tiny |
|--------|------------------|--------|-------------------|
| Speed | <1ms | 20-100ms | 20-60ms (est.) |
| Model size | 25 MB | 420 MB - 1.3 GB | ~12 MB (INT8) |
| Homophones | Good (known patterns) | Excellent (semantic) | Excellent |
| Grammar | None | Yes | Yes |
| Novel phrases | Poor | Good | Good |
| Missing words | None | Yes | Yes |
| Punctuation | None | Yes | Yes |
| Complexity | Simple | Moderate | Simple |
| Dependencies | None | Old (AllenNLP 0.8.4) | Modern (CTranslate2) |
| Pre-built models | N/A | Need conversion | ONNX ready |

**Verdict:** T5-efficient-tiny offers the best development path - modern dependencies, pre-built models, and integration via CTranslate2 (same backend as faster-whisper). For real-time transcription, run on final results only (not partial results).

---

## Files and Resources

**T5 Grammar Models (Pre-built ONNX):**
- `visheratin/t5-efficient-tiny-grammar-correction` - Smallest, fastest
- `visheratin/t5-efficient-mini-grammar-correction` - Better quality
- `onnx-community/t5-base-grammar-correction-ONNX` - Full T5-base
- HuggingFace models: https://huggingface.co/models?search=grammar+correction+onnx

**CTranslate2:**
- GitHub: https://github.com/OpenNMT/CTranslate2
- Quantization guide: https://opennmt.net/CTranslate2/quantization.html
- Python package: `pip install ctranslate2`

**GECToR:**
- Official repo: https://github.com/grammarly/gector
- Paper: https://arxiv.org/abs/2005.12592
- Pretrained models: Available via repo

**ONNX Runtime:**
- C API docs: https://onnxruntime.ai/docs/api/c/
- Quantization: https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html

**Current POS Service:**
- `src/pos_service.py` - Bigram/trigram disambiguation
- `tools/word-bigrams.tsv` - 932k bigram entries
- `tools/distinguishing-trigrams.tsv` - 113k trigram entries

**Talkie Faster-Whisper Integration:**
- `src/engines/faster_whisper_engine.py` - Coprocess engine (designed, not installed)
- `FASTER_WHISPER_INTEGRATION.md` - Architecture documentation

---

## Next Steps

1. **Install faster-whisper** in venv (brings CTranslate2 + ONNX Runtime)
2. **Download and convert** t5-efficient-tiny to CTranslate2 format
3. **Benchmark latency** on Intel Core Ultra 7 155H
4. **Create GEC coprocess service** following POS service pattern
5. **Test on logged homophone decisions** from `logs/homophone_decisions.jsonl`
6. **Compare accuracy** to current bigram approach
7. **Integrate into Talkie** as optional post-processing step
