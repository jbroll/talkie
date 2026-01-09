# Vosk Speech Recognition Parameters

This document explains the Vosk parameters used in Talkie and their effect on recognition speed and accuracy.

## Parameters

### max_alternatives

**Current setting:** Hardcoded to `1`

Controls the output format and decoding strategy:

| Value | Mode | Output Format | Speed | Use Case |
|-------|------|---------------|-------|----------|
| `0` | MBR (Minimum Bayes Risk) | `{"text": "..."}` | Fastest | When confidence not needed |
| `1` | N-best | `{"alternatives": [{"text": "...", "confidence": ...}]}` | Fast | Single best result with confidence |
| `2+` | N-best | Multiple alternatives ranked by likelihood | Slower | When you need alternative interpretations |

**Why we use 1:** We need the confidence score for filtering low-quality recognitions. Setting to `0` (MBR) only provides per-word confidence if `set_words` is enabled, which requires additional API calls. Setting to `1` gives us utterance-level confidence with minimal overhead.

**Note:** We don't actually use multiple alternatives in the code - we only look at `alternatives[0]`. The parameter is kept at 1 purely for the confidence score.

---

### beam

**Current setting:** Configurable, default `20`

Controls the beam search width during decoding. Beam search prunes unlikely hypotheses to speed up recognition.

| Value | Effect |
|-------|--------|
| Lower (5-10) | Faster, may miss correct transcription if it's not in top hypotheses |
| Medium (15-25) | Good balance of speed and accuracy |
| Higher (30-50) | Slower, more thorough search, better for difficult audio |

**Recommendation:** Start with 13-20. Only increase if you notice missing words in clear speech.

---

### lattice_beam

**Current setting:** Configurable, default `8`

Controls pruning during lattice generation. The lattice is a graph of possible word sequences used for generating alternatives and confidence scores.

| Value | Effect |
|-------|--------|
| Lower (2-5) | Faster lattice generation, less accurate confidence scores |
| Medium (6-10) | Good balance |
| Higher (12-20) | More accurate confidence, slower |

**Relationship to beam:** `lattice_beam` should generally be less than or equal to `beam`. A common ratio is `lattice_beam ≈ beam * 0.4`.

---

### sample_rate

**Current setting:** Detected from audio device (typically 44100 or 48000 Hz)

The audio sample rate passed to Vosk. Vosk internally resamples to 16000 Hz for recognition.

| Source Rate | Effect |
|-------------|--------|
| 16000 Hz | Native rate, no resampling overhead |
| 44100 Hz | Resampled internally by Vosk |
| 48000 Hz | Resampled internally by Vosk |

**Note:** Vosk handles resampling internally using `kaldi::LinearResample`. You don't need to resample audio before passing it to Vosk.

---

### words (not currently exposed)

**API:** `vosk_recognizer_set_words(recognizer, 1)`

When enabled, includes per-word timing and confidence in results:

```json
{
  "text": "hello world",
  "result": [
    {"word": "hello", "start": 0.5, "end": 0.8, "conf": 0.95},
    {"word": "world", "start": 0.9, "end": 1.2, "conf": 0.87}
  ]
}
```

**Why not enabled:** We only need utterance-level confidence, which `alternatives=1` provides. Per-word timing adds overhead and isn't used.

---

### partial_words (not currently exposed)

**API:** `vosk_recognizer_set_partial_words(recognizer, 1)`

When enabled, includes per-word information in partial (streaming) results. Adds overhead to real-time processing.

---

## Model Selection

Model choice has the biggest impact on speed:

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| `vosk-model-small-en-us-0.15` | 68 MB | ~3x faster | Good |
| `vosk-model-en-us-0.22-lgraph` | 205 MB | Baseline | Better |
| `vosk-model-en-us-0.22` | 1.8 GB | Slower | Best |

The `-lgraph` suffix indicates a smaller language model graph optimized for speed.

---

## Environment Variables

### OPENBLAS_NUM_THREADS

**Current setting:** `4` (set in `talkie.sh`)

Controls the number of threads OpenBLAS uses for matrix operations inside Vosk.

| Value | Effect |
|-------|--------|
| `1` | Single-threaded, lower CPU usage, slightly slower |
| `2` | Good balance for most systems |
| `4` | Sweet spot, diminishing returns beyond this |
| `6+` | Rarely helps, adds overhead |

**Note:** Vosk/Kaldi uses OpenBLAS for neural network inference. More threads can help but also increase CPU contention. Maximum practical benefit is around 4 threads.

---

### CPU Affinity (Intel Hybrid Architecture)

**Current setting:** Auto-detected in `talkie.sh`

On Intel hybrid CPUs (12th gen+), the wrapper script automatically pins the process to P-cores (performance cores) using `taskset`:

```bash
taskset -c 0-11 ./talkie.tcl
```

This prevents the scheduler from placing compute-intensive threads on slower E-cores (efficiency cores).

| Core Type | CPUs | Max Freq | Use |
|-----------|------|----------|-----|
| P-cores | 0-11 | 1400 MHz | Performance (pinned) |
| E-cores | 12-19 | 900 MHz | Efficiency |
| LP E-cores | 20-21 | 700 MHz | Low power |

**Note:** The detection is automatic. On non-hybrid CPUs, no pinning is applied.

---

## Performance Tuning Summary

**For faster recognition:**
1. Use smaller model (`vosk-model-small-en-us-0.15`)
2. Lower `beam` to 10-13
3. Lower `lattice_beam` to 4-6
4. Keep `alternatives` at 1 (not 0, unless you disable confidence filtering)

**For better accuracy:**
1. Use larger model (`vosk-model-en-us-0.22-lgraph` or full)
2. Increase `beam` to 25-35
3. Increase `lattice_beam` to 10-15

**Current defaults are balanced for real-time transcription with confidence filtering.**
