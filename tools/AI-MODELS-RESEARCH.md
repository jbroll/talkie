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

**Performance:**
- T5-small: 60M params, 240 MB, 100-300ms/sentence
- Better for complete rewrites
- 10x slower than GECToR

**Not recommended** for real-time use due to speed.

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

**Your hardware (Intel Core Ultra 7 155H):**
- Supports AVX2, VNNI instructions
- INT8 quantization gives 2-3x speedup
- Expected: 20-50ms for GECToR with ONNX Runtime

---

## C/C++ Integration Options

### ONNX Runtime (Recommended)

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

**Tcl integration:** Create C extension or use FFI (`ffidl`)

### llama.cpp / ggml

- Better for generative models (GPT-style)
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

### Best Overall: GECToR

**Why:**
1. Fixes homophones AND grammar in one pass
2. 10x faster than seq2seq alternatives
3. Parallel inference (non-autoregressive)
4. Well-tested, production-ready (Grammarly uses it)
5. Can be quantized for faster CPU inference

### Implementation Path

**Phase 1: Python Prototype (2-4 hours)**
```python
from gector import GECToR, predict

model = GECToR.from_pretrained('bert_0_gectorv2.th')
corrected = predict(model, tokenizer, "I has going to store")
# Output: "I have been going to the store"
```

**Phase 2: Persistent Service (1-2 days)**
- Similar to current POS service architecture
- Load model once, process requests via stdin/stdout
- Target: <100ms per correction

**Phase 3: ONNX/C Integration (1-2 weeks)**
- Export to ONNX format
- Create Tcl C extension
- Target: <50ms per correction

---

## Comparison: Bigrams vs AI Models

| Aspect | Bigrams/Trigrams | GECToR |
|--------|------------------|--------|
| Speed | <1ms | 20-100ms |
| Model size | 25 MB | 420 MB - 1.3 GB |
| Homophones | Good (known patterns) | Excellent (semantic) |
| Grammar | None | Yes |
| Novel phrases | Poor | Good |
| Missing words | None | Yes |
| Punctuation | None | Yes |
| Complexity | Simple | Moderate |

**Verdict:** GECToR provides significantly more value (grammar + homophones + punctuation) at acceptable latency cost (~50-100ms vs <1ms). For real-time transcription, run GECToR on final results only (not partial results).

---

## Files and Resources

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

---

## Next Steps

1. **Prototype GECToR** in Python, test on logged homophone decisions
2. **Benchmark latency** on actual hardware
3. **Compare accuracy** to current bigram approach
4. **Decide integration path** (Python service vs ONNX C extension)
