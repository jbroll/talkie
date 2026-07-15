# Speech Models

Talkie has three engines: **vosk** (Kaldi, streaming, in-process), **sherpa-onnx**
(in-process, auto-detects the model kind), and **faster-whisper** (Python coprocess).

Put models under `models/<engine>/`. For `sherpa-onnx`, drop **any** supported model
directory into `models/sherpa-onnx/` — they all appear together in the Settings →
Model dropdown, and the engine detects the kind automatically (`sherpa::detect_kind`).

## sherpa-onnx model kinds

| Kind | Files | Endpointing | Notes |
|---|---|---|---|
| online-transducer | encoder/decoder/joiner (`chunk`/`streaming`) | self | streaming, live partials |
| offline-transducer | encoder/decoder/joiner | external (batch) | Parakeet TDT, offline Zipformer |
| offline-ctc | single `model.onnx` | external (batch) | Parakeet CTC, NeMo/Zipformer/WeNet CTC |
| moonshine | preprocess/encode/uncached/cached | external (batch) | fast English |
| whisper | `*-encoder`/`*-decoder` + `*-tokens.txt` | external (batch) | robust, multilingual |
| sense-voice | single `model.onnx` | external (batch) | fast, multilingual, ITN |
| canary | encoder/decoder + tokens | external (batch) | NVIDIA, multilingual (needs matching `src_lang`) |

Streaming models give word-by-word partials and finalize themselves. Offline (batch)
models buffer the utterance and decode once when the VAD/partial-stability logic
decides speech has ended; decode time scales with utterance length and
`sherpa_num_threads`.

## Recommended English models (verified)

Install into `models/sherpa-onnx/` (download from
<https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models>, `tar xjf`):

| Model | Kind | Quality (EN) | Latency | Punct/Case | Best for |
|---|---|---|---|---|---|
| `sherpa-onnx-moonshine-tiny-en-int8` | moonshine | excellent | **~0.18s / 7s clip** | ✅ | **fast English dictation (recommended)** |
| `sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8` | offline-transducer | best | ~0.6s / 7s @ 4 threads | ✅ | max English accuracy |
| `sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8` | offline-ctc | good | very fast | ✅ | small/fast |
| `sherpa-onnx-whisper-tiny.en` | whisper | good | moderate (autoregressive) | ✅ | robustness / multilingual family |
| `sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8` | canary | high | fast | ✅ | multilingual (en/es/de/fr) |
| `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-*` | sense-voice | fair (EN) | very fast | ✅ (+ITN) | speed / multilingual, ITN (numbers→digits) |
| `sherpa-onnx-streaming-zipformer-en-2023-06-26` | online-transducer | fair | real-time partials | ❌ (ALL-CAPS) | live word-by-word, lowest latency |

Latencies are indicative (int8, fast multi-core CPU). Parakeet decode speed depends
heavily on `sherpa_num_threads` (2→4 threads ≈ 3.6× faster).

## Install helpers
- `tools/install-sherpa-onnx-lib.sh <url>` — the sherpa-onnx C shared library + headers (required for the engine).
- `tools/install-parakeet-model.sh` — Parakeet TDT 0.6B into `models/sherpa-onnx/`.

## Vosk
- `models/vosk/vosk-model-en-us-0.22-lgraph` (streaming, in-process). Emits ALL-CAPS,
  no punctuation; Talkie lowercases and sentence-cases via `textproc`.

## Notes
- ALL-CAPS engines (Vosk, streaming Zipformer) are lowercased by Talkie so sentence
  capitalization applies. Parakeet/Moonshine/Whisper/Canary emit proper case+punctuation
  and are left as-is.
- STT always runs on **CPU** — the prebuilt sherpa-onnx library has no Intel-NPU ASR
  path. (The VAD "Device" CPU/NPU option is for **Silero VAD only**.)
