# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Talkie is a modular speech-to-text application for Linux. See [README.md](README.md) for full documentation including architecture, installation, and usage.

## Quick Reference

### Key Files
- `src/engine.tcl` - Audio + Processing workers (PortAudio capture, VAD, STT)
- `src/stt.tcl` - Common `stt::` engine dispatch (in-process critcl engines)
- `src/finalization.tcl` - `engine::should_finalize` (self-endpoint vs partial-stability)
- `src/sherpa/` - sherpa-onnx critcl binding (streaming Zipformer)
- `src/output.tcl` - Post-processing (filters, textproc) + uinput typing
- `src/audio.tcl` - Result display, transcription state, device enumeration
- `src/worker.tcl` - Reusable worker thread abstraction

### Threading Model
- **Audio Worker**: PortAudio callbacks, queues to Processing (never blocks)
- **Processing Worker**: VAD + speech recognition (40Hz), forwards finals to Output
- **Output Worker**: post-processing (killword + confidence filter, `textproc`) + keyboard simulation via uinput
- **Main Thread**: GUI (5Hz updates), result display
- Pipeline: Audio → Processing → Output
- Communication via `thread::send -async`

> The GEC/homophone pipeline (grammar/punctuation/homophone correction via
> OpenVINO) was removed — the experiments were not reliable. `src/gec/`,
> `src/gec_worker.tcl` history, and `models/gec/` are retired; the punct/cap
> and homophone stages no longer run. Engines emit their own text.

### Engine abstraction
- Common contract in `src/stt.tcl` (`stt::` namespace): `create`, `process`→`{partial endpoint}`, `final`→`{text confidence}`, `reset`, `destroy`. All engines are in-process (critcl).
- Registry (`engine.tcl`) declares per-engine `endpointing` (`self`|`external`) and `emits_partials`.
- End-of-utterance: `self`-endpoint engines (sherpa-onnx) finalize on the recognizer's `endpoint`; `external` engines use `engine::should_finalize` (energy-silence OR partial-stability) in `src/finalization.tcl`.
- Engines: `vosk` (critcl), `sherpa-onnx` (critcl, `src/sherpa/`) — all in-process.
- `sherpa-onnx` auto-detects the model kind from the model dir (`sherpa::detect_kind`): streaming Zipformer (online, self-endpoint) / offline transducer (Parakeet TDT) / offline CTC (Parakeet CTC, NeMo). All sherpa models live under `models/sherpa-onnx/`. The old Python `sherpa` coprocess was removed.

### State Management
- `::transcribing` global variable controls transcription state
- Variable traces synchronize GUI and audio processing
- External control via `~/.talkie` file (JSON)
- Configuration in `~/.talkie.conf` (JSON with auto-save)

## Development Guidelines

### Architecture Principles
- **Minimal Code**: Prefer one-liners over bloated functions
- **Trace-Based**: Use variable traces for state synchronization
- **Worker Threads**: Audio and output on dedicated threads (worker.tcl)
- **Async Communication**: `thread::send -async` for cross-thread messaging

### Tcl Best Practices
- Always brace `expr` expressions: `expr {$x + $y}`
- Use `[list]` for command construction (avoid string concatenation)
- Namespace all code with `namespace eval`
- Extract complex bind logic to named procs

### Adding Features
1. **State Changes**: Modify `::transcribing` trace handlers
2. **GUI Updates**: Add to existing trace callbacks
3. **Configuration**: Add to `config` array with auto-save trace
4. **New Engine**: Add entry to `engine_registry` in engine.tcl

## Build & Test

```bash
cd src
make build          # Build all critcl packages
./talkie.sh         # Run application (sets up OpenVINO paths)
```

## Model Data

### Vosk Models
- Base model: `models/vosk/vosk-model-en-us-0.22-lgraph/` (with `compile/` staging tree for rebuilds)
- Custom builds: `models/vosk/vosk-model-en-us-0.22-lgraph-YYYY-MM-DD/` (date-stamped, produced by `tools/build-custom-vosk.sh`)
- Historical custom: `models/vosk/lm-test/` (early SRILM-era build; kept for regression comparison, not canonical)

### sherpa-onnx Model
- Streaming Zipformer: `models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/` (use `.int8.onnx` variants). Install the C lib with `tools/install-sherpa-onnx-lib.sh <url>`.

### GEC Models (retired)
- `models/gec/` (`distilbert-punct-cap.onnx`, `electra-small-generator.onnx`) and `data/homophones.json` are no longer used — the GEC pipeline was removed. Files remain on disk but nothing loads them.

See `tools/BUILD-CUSTOM-LGRAPH.md` for building custom language models.
