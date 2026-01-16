# NPU Grammar Error Correction Benchmarks

Benchmark results comparing Intel Core Ultra NPU vs CPU for GEC models using OpenVINO 2026.0.

## Hardware

- **CPU**: Intel Core Ultra 7 155H (16 P-cores + E-cores)
- **NPU**: Intel NPU Platform 3720 (PCI 8086:7D1D)
- **Runtime**: OpenVINO 2026.0 with PLUGIN compiler (libnpu_mlir_compiler.so)

## Original Plan (AI-MODELS-RESEARCH.md)

The research recommended a hybrid approach:

| Model | Role | CPU Latency (CTranslate2) | Size |
|-------|------|---------------------------|------|
| ELECTRA-Small MLM | Homophones | 7.6ms | ~50 MB |
| T5-efficient-tiny | Grammar | 3.7ms | 16 MB |
| **Combined** | Full correction | ~12ms | - |

## NPU Benchmark Results

### Encoder-Only Models (Work Great on NPU)

| Model | Size | NPU Latency | CPU Latency | NPU Speedup | Use Case |
|-------|------|-------------|-------------|-------------|----------|
| **ELECTRA-Small Generator (MLM)** | 67 MB | **3.61 ms** | 6.52 ms | **1.8x** | Homophones |
| ELECTRA-Small Discriminator | 52 MB | 2.54 ms | 13.36 ms | 5.3x | Token detection |
| T5-efficient-tiny encoder | 44 MB | 2.55 ms | 3.89 ms | 1.5x | Encoding |
| T5-small encoder | 35 MB | 42.4 ms | 58.0 ms | 1.4x | Encoding |

**Note**: The Generator (MLM) model is what we need for homophone detection, not the Discriminator.

### Seq2Seq Decoders (NPU Limitation)

| Model | Component | NPU Status | Reason |
|-------|-----------|------------|--------|
| T5-efficient-tiny | Decoder | **FAIL** | Dynamic shapes (relative positional encoding) |
| T5-small | Decoder | **FAIL** | Dynamic KV-cache dimensions |
| T5-base | Decoder | **FAIL** | Upper bounds not specified errors |

**Root Cause**: T5 uses relative positional encodings that create dynamic tensor shapes during attention computation. NPU requires static shapes or bounded ranges for all dimensions.

### Why ELECTRA Works on NPU

```json
// ELECTRA config.json
{
  "position_embedding_type": "absolute",  // <-- Static shapes!
  "max_position_embeddings": 512
}
```

Absolute position embeddings have fixed dimensions regardless of input length. T5's relative positions compute attention biases dynamically based on sequence positions.

## Revised Multi-Model Pipeline

With NPU acceleration, we can run a comprehensive 3-stage correction pipeline:

```
┌─────────────────────────────────────────────────────────────┐
│                ASR Output (lowercase, no punctuation)        │
│            "i went to there house yesterday"                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│    Stage 1: DistilBERT Punctuation + Capitalization         │
│                    NPU: 4.41ms (4.0x faster)                │
│         Adds: periods, commas, questions, proper caps       │
│      "I went to there house yesterday."                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│    Stage 2: ELECTRA-Small Generator (MLM) - Homophones      │
│                    NPU: 3.61ms (1.8x faster)                │
│         Fixes: their/there, your/you're, etc.               │
│      "I went to their house yesterday."                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│    Stage 3: T5-efficient-tiny (Grammar)                     │
│                 CPU (CTranslate2): 3.7ms                    │
│     Fixes: subject-verb agreement, tense, articles          │
│      "I went to their house yesterday."                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Corrected Text                             │
└─────────────────────────────────────────────────────────────┘
```

### Pipeline Latency Budget

| Stage | Model | Device | Latency | Task |
|-------|-------|--------|---------|------|
| 1 | DistilBERT punct+cap | NPU | 4.41 ms | Punctuation, Capitalization |
| 2 | ELECTRA-Small Generator | NPU | 3.61 ms | Homophones |
| 3 | T5-efficient-tiny | CPU | 3.7 ms | Grammar |
| **Total** | - | Hybrid | **~11.7 ms** | Full correction |

### All Models Benchmarked

| Model | Task | Size | NPU | CPU | Speedup |
|-------|------|------|-----|-----|---------|
| DistilBERT punct+cap | Punct+Caps | 254 MB | **4.41 ms** | 17.72 ms | **4.0x** |
| ELECTRA-Small Generator | Homophones | 67 MB | **3.61 ms** | 6.52 ms | **1.8x** |
| T5-efficient-tiny | Grammar | 16 MB | ❌ | 3.7 ms | N/A |

**Key Insight**: NPU enables running 2 encoder models in ~8ms total, leaving CPU free for T5 decoder.

## Model Files

```
models/gec/
├── distilbert-punct-cap.onnx        # 254 MB - NPU, punct+caps
├── electra-small-generator.onnx     # 67 MB - NPU, homophones (90%)
└── t5-efficient-tiny-ct2/           # 16 MB - CPU, grammar (CTranslate2)
```

**Total: 337 MB** for complete 3-stage correction pipeline.

## Tools

### hf-to-onnx - Export HuggingFace Models to ONNX

Simple CLI tool to export transformer models for NPU inference:

```bash
# Activate Python venv with torch/transformers
source ~/venv/optimum/bin/activate

# Export MLM model (auto-detects task)
./tools/hf-to-onnx google/electra-small-generator models/gec/electra-gen.onnx

# Export token classification model
./tools/hf-to-onnx unikei/distilbert-base-re-punctuate models/gec/punct-cap.onnx

# Custom sequence length
./tools/hf-to-onnx google/electra-small-generator model.onnx --seq-len 128
```

Options:
- `--seq-len N` - Input sequence length (default: 64)
- `--task {mlm,token-classification,sequence-classification}` - Override auto-detection

## Running Benchmarks

### Environment Setup

```bash
export LD_LIBRARY_PATH=/home/john/pkg/linux-npu-driver/build/lib:/home/john/pkg/openvino-src/bin/intel64/Release
```

### NPU Config

```bash
cat /tmp/npu_plugin_config.json
{
    "NPU": {
        "NPU_COMPILER_TYPE": "PLUGIN"
    }
}
```

### Benchmark Commands

```bash
# ELECTRA Generator on NPU (homophones)
benchmark_app -m models/gec/electra-small-generator.onnx \
    -d NPU -load_config /tmp/npu_plugin_config.json \
    -niter 100 -hint latency

# DistilBERT on NPU (punctuation + capitalization)
benchmark_app -m models/gec/distilbert-punct-cap.onnx \
    -d NPU -load_config /tmp/npu_plugin_config.json \
    -niter 100 -hint latency

# Compare with CPU
benchmark_app -m models/gec/electra-small-generator.onnx \
    -d CPU -niter 100 -hint latency
```

## Homophone Accuracy Tests

Tests run on 10 homophone cases from AI-MODELS-RESEARCH.md:

| Model | Size | NPU Latency | CPU Latency | NPU Speedup | Accuracy |
|-------|------|-------------|-------------|-------------|----------|
| **ELECTRA-Small Generator (MLM)** | **67 MB** | **3.61 ms** | 6.52 ms | 1.8x | **90%** ⭐ |
| T5-efficient-tiny | 16 MB | N/A | 5.3ms (CT2) | - | 50% |

**Recommendation: ELECTRA-Small Generator** - Best balance of size (67 MB), speed (3.61ms), and accuracy (90%).

### Test Cases

| Input | Expected | ELECTRA-Gen | T5-tiny |
|-------|----------|-------------|---------|
| "I went to there house" | their | ✓ | ✗ |
| "Your going to the store" | You're | ✓ | ✗ |
| "its wrong to do that" | It's | ✗ | ✓ |
| "I don't no the answer" | know | ✓ | ✓ |
| "I can here you clearly" | hear | ✓ | ✓ |
| "Turn write at the light" | right | ✓ | ✗ |
| "Check the whether forecast" | weather | ✓ | ✗ |
| "He through the ball far" | threw | ✓ | ✗ |
| "The hole thing is wrong" | whole | ✓ | ✓ |
| "I want to by a car" | buy | ✓ | ✓ |

### Key Insight

MLM models like ELECTRA Generator use bidirectional context to score word probabilities, making them excellent for homophones. T5 grammar models are trained for grammatical errors, not spelling/homophone correction.

## Key Findings

1. **Encoder-only models excel on NPU** (1.8-4x speedup for ELECTRA, DistilBERT)
2. **Seq2seq decoders fail** due to dynamic relative positional encoding
3. **Absolute position embeddings = NPU compatible**
4. **Hybrid approach optimal**: NPU for token classification/MLM, CPU for generation

## Comparison with Original Plan

| Metric | Original Plan | NPU Results | Verdict |
|--------|---------------|-------------|---------|
| ELECTRA latency | 7.6ms (CPU) | **3.61ms (NPU)** | 1.8x faster |
| T5-tiny full | 3.7ms (CPU) | Encoder only: 2.55ms | Encoder works |
| T5 decoder | 3.7ms (CPU) | **Not supported** | Use CTranslate2 |
| Total pipeline | ~12ms | **~11.7ms hybrid** | 3% improvement |
| NPU benefit | None | punct+homophones | CPU freed for grammar |

## Next Steps

1. **Integrate ELECTRA ONNX** into Talkie via OpenVINO C API
2. **Integrate DistilBERT punct+cap ONNX** for punctuation and capitalization
3. **Keep CTranslate2** for T5 grammar correction (fast, proven)

## References

- [NPU-BUILD-GUIDE.md](./NPU-BUILD-GUIDE.md) - OpenVINO NPU build instructions
- [AI-MODELS-RESEARCH.md](./AI-MODELS-RESEARCH.md) - Original model research
- [OpenVINO NPU Plugin](https://docs.openvino.ai/2024/openvino-workflow/running-inference/inference-devices-and-modes/npu-device.html)
