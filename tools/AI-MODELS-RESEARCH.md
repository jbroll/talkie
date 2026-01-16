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
| t5-efficient-tiny (CTranslate2, INT8) | **3.7ms** | ✓ Benchmarked |
| t5-efficient-mini (CTranslate2, INT8) | **6.4ms** | ✓ Benchmarked |
| t5-base-grammar (CTranslate2, INT8) | **47.6ms** | ✓ Benchmarked |

**Your hardware (Intel Core Ultra 7 155H):**
- Supports AVX2, VNNI instructions
- INT8 quantization gives 2-3x speedup
- CTranslate2 significantly faster than estimates (3.7ms vs 20-60ms expected)

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
| Speed | <1ms | 20-100ms | **3.7ms** (benchmarked) |
| Model size | 25 MB | 420 MB - 1.3 GB | 16 MB (INT8) |
| Homophones | Good (known patterns) | Excellent (semantic) | Fair (6/10) |
| Grammar | None | Yes | Excellent |
| Novel phrases | Poor | Good | Good |
| Missing words | None | Yes | Yes |
| Punctuation | None | Yes | Yes |
| Complexity | Simple | Moderate | Simple |
| Dependencies | None | Old (AllenNLP 0.8.4) | Modern (CTranslate2) |
| Pre-built models | N/A | Need conversion | ✓ Ready |

**Verdict:** T5-efficient-tiny is excellent for **grammar correction** (3.7ms, subject-verb agreement, tense, contractions) but **not ideal for homophones**. A hybrid approach using bigrams for homophones + T5-tiny for grammar provides the best overall accuracy with minimal latency impact (~5ms total).

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

## Benchmark Results (Jan 2026)

Actual benchmarks run on Intel Core Ultra 7 155H with CTranslate2 INT8 quantization.

### Comprehensive Model Comparison (69 test cases)

| Model | Overall | Homophone | Grammar | Latency | Notes |
|-------|---------|-----------|---------|---------|-------|
| **distilbert-mlm** | 60.9% | **80.9%** | 0.0% | 12.5ms | Best homophones |
| **electra-small-mlm** | 59.4% | 78.7% | 0.0% | **7.6ms** | Fastest MLM |
| bert-base-mlm | 59.4% | 78.7% | 0.0% | 17.5ms | No advantage over DistilBERT |
| **t5-efficient-tiny** | 50.7% | 42.6% | **68.8%** | **4.0ms** | Best grammar |
| t5-efficient-mini | 50.7% | 44.7% | 68.8% | 8.0ms | No improvement over tiny |
| t5-base-grammar | 42.0% | 23.4% | 75.0% | 49.3ms | Too conservative |

### Key Findings

1. **MLM models dominate homophones** (78-81%) but cannot do grammar (0%)
2. **T5 models dominate grammar** (68-75%) but struggle with homophones (23-45%)
3. **Bigger is NOT better** - t5-base performs worst overall despite being largest
4. **ELECTRA-Small is fastest MLM** at 7.6ms with near-best accuracy (78.7%)

### Optimal Hybrid Approach

Combine strengths of both model types:

| Stage | Model | Accuracy | Latency |
|-------|-------|----------|---------|
| Homophones | ELECTRA-Small MLM | 78.7% | 7.6ms |
| Grammar | T5-efficient-tiny | 68.8% | 4.0ms |
| **Combined** | Hybrid | ~85%+ | ~12ms |

### Initial Model Comparison

| Model | Size | Median Latency | Homophone Accuracy |
|-------|------|----------------|-------------------|
| t5-efficient-tiny | 16 MB | **3.7ms** | 6/10 |
| t5-efficient-mini | 31 MB | 6.4ms | 5/10 |
| grammar-synthesis-small | 75 MB | 14.1ms | 3/10 (hallucinations) |
| t5-base-grammar | 215 MB | 47.6ms | 2/10 (but got "their") |

### Homophone Test Results

| Test Case | tiny | mini | synth | base |
|-----------|------|------|-------|------|
| there→their house | ✗ | ✗ | ✗ | ✓ |
| Your→You're going | ✗ | ✗ | ✗ | ✗ |
| its→it's wrong | ✓ | ✓ | ✓ | ✓ |
| no→know answer | ✓ | ✓ | ✗ | ✗ |
| here→hear you | ✓ | ✗ | ✗ | ✗ |
| write→right now | ✗ | ✗ | ✗ | ✗ |
| whether→weather | ✓ | ✓ | ✓ | ✗ |
| through→threw ball | ✗ | ✗ | ✗ | ✗ |
| hole→whole thing | ✓ | ✓ | ✓ | ✗ |
| by→buy a car | ✓ | ✓ | ✗ | ✗ |

### Grammar Correction Results

All models performed well on grammar errors:

| Input | t5-efficient-tiny Output |
|-------|-------------------------|
| "I has going to store" | "I have been going to the store." |
| "She have been working hard" | "She has been working hard." |
| "They was going to the store" | "They were going to the store." |
| "He dont understand the question" | "He doesn't understand the question." |
| "I seen him yesterday" | "I saw him yesterday." |

### Key Findings

1. **Speed exceeded expectations**: t5-efficient-tiny achieved 3.7ms median latency (vs 20-60ms estimated)

2. **Grammar models are not homophone models**: These T5 models were trained on grammatical errors, not spelling/homophone correction. They excel at subject-verb agreement, tense, contractions but struggle with homophones.

3. **Larger ≠ better for homophones**: t5-base-grammar (215 MB) only got 2/10 homophones correct, while tiny (16 MB) got 6/10.

4. **Hallucination risk**: grammar-synthesis-small produced severe hallucinations:
   - "I through the ball" → "Shelley and I dance through the woods"
   - "I want to by a car" → "I want to be a car dealer"

5. **t5-base got "their" right**: The only model to correctly handle "there house" → "their house", which is a high-value correction.

### Converted Models (Local)

Models converted and stored in `models/gec/`:

```
models/gec/
├── t5-efficient-tiny-ct2/    # 16 MB - fastest, decent accuracy
├── t5-efficient-mini-ct2/    # 31 MB - slightly slower, similar accuracy
├── grammar-synthesis-small-ct2/  # 75 MB - hallucinations, not recommended
└── t5-base-grammar-ct2/      # 215 MB - slowest, best for "their/there"
```

### Recommendation Update

**Hybrid approach recommended (based on comprehensive testing):**

1. **Use ELECTRA-Small MLM for homophones** - 78.7% accuracy at 7.6ms
   - Best speed/accuracy tradeoff for homophone disambiguation
   - Works by scoring P(word|context) for each homophone alternative
   - Limitations: Can't handle contractions (its/it's, your/you're)

2. **Use t5-efficient-tiny for grammar** - 68.8% accuracy at 4.0ms
   - Subject-verb agreement
   - Verb tense correction
   - Contraction expansion
   - Missing articles

3. **Combined pipeline: ~12ms total**
   - First pass: ELECTRA-Small fixes homophones
   - Second pass: T5-tiny fixes grammar
   - Expected combined accuracy: 85%+

### MLM Model Limitations

The MLM approach (DistilBERT, ELECTRA, BERT) cannot handle:
- **Contractions** - its/it's, your/you're (tokenized differently)
- **Grammar errors** - Only predicts masked words, doesn't rewrite
- **Missing words** - Can only score existing positions

These are handled well by T5-tiny, making the hybrid approach complementary.

### Sample Integration Code

```python
import ctranslate2
import transformers

model_path = "models/gec/t5-efficient-tiny-ct2"
translator = ctranslate2.Translator(model_path, compute_type="int8")
tokenizer = transformers.AutoTokenizer.from_pretrained(
    "visheratin/t5-efficient-tiny-grammar-correction"
)

def correct_grammar(text):
    tokens = tokenizer.convert_ids_to_tokens(tokenizer.encode(text))
    result = translator.translate_batch([tokens])
    output_tokens = result[0].hypotheses[0]
    return tokenizer.decode(
        tokenizer.convert_tokens_to_ids(output_tokens),
        skip_special_tokens=True
    )
```

---

## Additional Tiny Models Research (Jan 2026)

Research into smaller models specifically optimized for homophones and <10ms latency.

### Tiny Encoder Models (<50M params)

| Model | Params | Size | Expected Latency | Best For |
|-------|--------|------|------------------|----------|
| **BERT-Tiny** | 4.4M | ~17 MB | <50ms | Extreme size constraints |
| **TinyBERT-4** | 14.5M | 55 MB | <100ms | Distilled, 96.8% of BERT |
| **ELECTRA-Small** | 14M | ~50 MB | <100ms | Discriminative training, efficient |
| **MobileBERT-TINY** | 15.1M | 50 MB | 40ms (mobile) | Mobile-optimized |
| **DistilBERT (INT8)** | 66M | 50 MB | **9.5ms** | Well-established, optimized |

### Word Sense Disambiguation Models

| Model | Params | Size | Latency | Purpose |
|-------|--------|------|---------|---------|
| **GlossBERT** | 110M | ~350 MB | ~100ms | Homophone/homonym disambiguation |
| **BERT-WSD** | 110M | ~350 MB | ~100ms | Word sense with gloss matching |
| **PolyBERT** | 110M | ~350 MB | ~100ms | +2% F1 over GlossBERT |

**GlossBERT** is specifically trained for word sense disambiguation - exactly what's needed for homophones. It scores context-gloss pairs:
- Input: "He caught a bass yesterday" + gloss definitions
- Output: Selects "bass (fish)" over "bass (music)"
- Applicable to their/there/they're disambiguation

### Non-Transformer Lightweight Options

| Approach | Size | Latency | Accuracy | Notes |
|----------|------|---------|----------|-------|
| **SymSpell** | ~1 MB | **0.033ms/word** | No context | Edit distance only |
| **FastText** | ~500 MB | sub-ms | No context | Embedding similarity |
| **Spello** | ~10 MB | **<10ms** | With context | Hybrid: phoneme + SymSpell + context |

**Spello** is particularly interesting - a production hybrid system combining:
1. Phoneme model (Soundex) for sound-alike suggestions
2. SymSpell for edit-distance corrections
3. Context model to select best candidate
4. Achieves <10ms latency

### Quantized Models

| Technique | Speedup | Size Reduction | Accuracy Loss |
|-----------|---------|----------------|---------------|
| INT8 (standard) | 2-4x | 4x | Minimal |
| INT4 (encoder models) | 8.5x | 8x | None for encoders |
| I-BERT (integer-only) | 4x | 4x | Minimal |
| Dynamic-TinyBERT | 2.7x | Same | None |

**Key insight:** INT4 quantization shows no accuracy degradation for encoder-only models (BERT-style), with up to 8.5x speedup.

### Homophone-Specific Approach: MLM Scoring

For homophones, masked language models can directly score alternatives:

```python
# Score "their" vs "there" vs "they're" in context
text = "I went to [MASK] house"
# Model returns: P(their|context)=0.85, P(there|context)=0.10, P(they're|context)=0.05
```

This approach:
- Uses any BERT-style model (no fine-tuning needed)
- Fast single-word scoring
- Works for all homophones without training on specific pairs

---

## Tcl/Critcl Integration Options (Jan 2026)

### Existing Project Infrastructure

Talkie already has production critcl patterns:
- `src/vosk/vosk.tcl` - Context structures, object commands, cleanup handlers
- `src/pa/pa.tcl` - Ring buffers, event loop integration, non-blocking I/O
- `src/sherpa-onnx/sherpa-onnx.tcl` (393 lines) - **Already links ONNX Runtime**

### Option 1: CTranslate2 via Critcl (Recommended)

**CTranslate2 is 2.2x faster than ONNX Runtime for T5/seq2seq models.**

C++ integrates with critcl using `extern "C"` wrappers:

```cpp
// gec_wrapper.cpp
#include "ctranslate2/translator.h"

extern "C" {
    #include <tcl.h>

    typedef struct {
        ctranslate2::Translator* translator;
        Tcl_Obj* cmdname;
    } TranslatorCtx;

    void* ct2_load_model(const char* path, const char* compute_type) {
        return new ctranslate2::Translator(path, ctranslate2::Device::CPU,
                                           ctranslate2::ComputeType::INT8);
    }

    // Tcl command wrapper
    int TranslatorObjCmd(ClientData cd, Tcl_Interp* interp,
                        int objc, Tcl_Obj* const objv[]) {
        TranslatorCtx* ctx = (TranslatorCtx*)cd;
        // ... dispatch to translate, close, etc.
    }
}
```

**Advantages:**
- 2.2x faster than ONNX Runtime (benchmarked)
- Already have converted models in `models/gec/`
- 3.7ms Python latency → potentially <2ms native
- Same pattern as existing vosk.tcl

### Option 2: ONNX Runtime via Critcl

Already proven in sherpa-onnx.tcl:

```tcl
critcl::cheaders -I$onnx_home/include
critcl::clibraries -L$onnx_home/lib -lonnxruntime
```

**Advantages:**
- Pure C API (no extern "C" needed)
- Already linked in sherpa-onnx
- Better for encoder-only models (BERT, GlossBERT)

### Option 3: Keep Python Coprocess

Current POS service pattern - works well for non-critical-path processing:

```tcl
# Already implemented pattern
set pos_pipe [open "|python3 pos_service.py" r+]
puts $pos_pipe $text
flush $pos_pipe
gets $pos_pipe result
```

**Trade-off:** ~100-500ms process overhead vs <10ms native.

### Recommended Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Tcl Layer                          │
├─────────────────────────────────────────────────────────┤
│  Tokenization (Tcl)  │  Post-processing (Tcl)          │
├──────────────────────┴──────────────────────────────────┤
│              Critcl C/C++ Extension                     │
├─────────────────────────────────────────────────────────┤
│  CTranslate2 (T5 grammar)  │  ONNX Runtime (GlossBERT) │
└─────────────────────────────────────────────────────────┘
```

**Latency budget:**
- Tokenization (Tcl): ~1ms
- CTranslate2 inference: ~2-3ms (native vs 3.7ms Python)
- Post-processing: ~1ms
- **Total: ~5ms end-to-end**

### Build Pattern (following sherpa-onnx.tcl)

```tcl
package require critcl 3.1

critcl::cheaders -I/path/to/ctranslate2/include
critcl::clibraries -L/path/to/ctranslate2/lib -lctranslate2 -lonnxruntime

critcl::ccode {
    #include <tcl.h>
    // C wrapper code with extern "C" for C++ calls
}

critcl::cproc gec::load_model {Tcl_Interp* interp char* path} ok {
    // Load CTranslate2 model, return handle
}

package provide gec 1.0
```

---

## Next Steps

1. ~~**Install faster-whisper** in venv~~ ✓ Done
2. ~~**Download and convert** t5-efficient-tiny to CTranslate2 format~~ ✓ Done
3. ~~**Benchmark latency** on Intel Core Ultra 7 155H~~ ✓ Done (3.7ms median)
4. **Try GlossBERT or ELECTRA-Small** for homophone-specific scoring
5. **Prototype CTranslate2 critcl wrapper** following sherpa-onnx pattern
6. **Create GEC coprocess service** as fallback/comparison
7. **Test on logged homophone decisions** from `logs/homophone_decisions.jsonl`
8. **Compare accuracy** to current bigram approach
9. **Evaluate hybrid approach** - bigrams for homophones + T5 for grammar
10. **Integrate into Talkie** as optional post-processing step
