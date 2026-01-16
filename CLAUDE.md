# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Talkie is a modular speech-to-text application for Linux. See [README.md](README.md) for full documentation including architecture, installation, and usage.

## Quick Reference

### Key Files
- `src/engine.tcl` - Audio processing on worker thread (PortAudio + Vosk)
- `src/audio.tcl` - Result parsing, GEC coordination, transcription state
- `src/worker.tcl` - Reusable worker thread abstraction
- `src/gec/` - Grammar error correction (punctuation, capitalization, homophones)

### Threading Model
- **Engine Worker**: Audio callbacks + speech recognition (40Hz)
- **Output Worker**: Keyboard simulation via uinput
- **Main Thread**: GUI (5Hz updates), GEC processing, result display
- Communication via `thread::send -async`

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
./talkie.tcl        # Run application
```

## Model Data

### Vosk Models
- Base model: `models/vosk/vosk-model-en-us-0.22-lgraph/`
- Custom model: `models/vosk/lm-test/` (with domain vocabulary)

### GEC Models
- Punctuation/capitalization: ONNX BERT model via pipeline.tcl
- Homophones: JSON dictionary at `data/homophones.json`

See `tools/BUILD-CUSTOM-LGRAPH.md` for building custom language models.
