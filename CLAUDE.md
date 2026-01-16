# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Talkie is a modular speech-to-text application for Linux. It provides
real-time audio transcription with intelligent keyboard simulation,
featuring a modern GUI, configurable audio processing, and support for
multiple speech recognition engines.

## Architecture

```
talkie/src/
├── talkie.tcl                   # Main application orchestrator
├── config.tcl                   # Configuration and state management
├── engine.tcl                   # Speech engine with integrated audio (worker thread)
├── audio.tcl                    # Result parsing and transcription state
├── worker.tcl                   # Reusable worker thread abstraction
├── output.tcl                   # Keyboard output (worker thread)
├── threshold.tcl                # Confidence threshold management
├── textproc.tcl                 # Text processing and voice commands
├── coprocess.tcl                # External engine communication
├── ui-layout.tcl                # Tk UI layout and widgets
├── display.tcl                  # Text display and visualization
├── vosk.tcl                     # Vosk speech engine integration
├── gec/                         # Grammar/Error Correction pipeline
│   ├── gec.tcl                 # GEC coordinator
│   ├── pipeline.tcl            # ONNX inference pipeline
│   ├── punctcap.tcl            # Punctuation and capitalization
│   ├── homophone.tcl           # Homophone correction
│   └── tokens.tcl              # BERT token constants
├── uinput/                      # Keyboard simulation (critcl)
├── pa/                          # PortAudio bindings (critcl)
├── vosk/                        # Vosk bindings (critcl)
└── audio/                       # Audio processing bindings (critcl)
```

### Core Components (Tcl)

#### Main Application (talkie.tcl)
- Global state management with `::transcribing` variable
- Trace-based architecture for state synchronization
- Module initialization and coordination
- Package requirements and auto_path setup

#### Configuration Management (config.tcl)
- JSON-based configuration in `~/.talkie.conf`
- State file persistence in `~/.talkie`
- File watching with `jbr::filewatch` for external changes
- Auto-save traces on configuration changes
- Minimal load/save functions using `cat` and `echo`

#### Engine (engine.tcl) - Worker Thread
- Integrates PortAudio stream directly on worker thread
- Audio callbacks fire on worker, bypassing main thread
- Voice activity detection with adaptive threshold
- Speech recognition (Vosk critcl or coprocess engines)
- Sends results to main thread via `thread::send -async`
- UI updates throttled to 5Hz

#### Audio/Results (audio.tcl) - Main Thread
- Parses recognition results (JSON from Vosk)
- Coordinates GEC processing (punctuation, homophones)
- Manages transcription state
- Device enumeration for configuration

#### Output (output.tcl) - Worker Thread
- Keyboard simulation via uinput
- Runs on dedicated worker thread
- Async text output to avoid blocking

#### GEC Pipeline (gec/)
- **pipeline.tcl**: ONNX Runtime inference for BERT models
- **punctcap.tcl**: Adds punctuation and capitalization
- **homophone.tcl**: Corrects homophones using context
- **tokens.tcl**: BERT token constants (PAD, CLS, SEP, etc.)

#### GUI Interface (ui-layout.tcl)
- Tk-based responsive interface
- Real-time audio energy and confidence display (5Hz updates)
- Automatic button updates via `::transcribing` trace
- Device selection and parameter adjustment

#### Display Management (display.tcl)
- Text output formatting and display
- Partial and final result handling
- Energy level and confidence visualization
- Rolling buffer management

### State Management Architecture

#### Trace-Based Synchronization
- **`::transcribing` Global Variable**: Central state for transcription control
- **Transcription Trace**: Automatically starts/stops audio processing when state changes
- **GUI Trace**: Updates button appearance when transcription state changes
- **File Watcher**: Monitors `~/.talkie` file for external state changes

#### State Persistence
- **Configuration**: `~/.talkie.conf` (JSON format with auto-save)
- **Transcription State**: `~/.talkie` (JSON format: `{"transcribing": true/false}`)
- **File Watching**: 500ms interval monitoring for external control

### Threading Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Main Thread                               │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────────┐ │
│  │   GUI   │  │  GEC    │  │ Display │  │ Result Processing   │ │
│  │ (5Hz)   │  │Pipeline │  │         │  │ (parse_and_display) │ │
│  └─────────┘  └─────────┘  └─────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
        ▲                                          ▲
        │ thread::send -async                      │
        │ (UI updates)                             │ thread::send -async
        │                                          │ (recognition results)
┌───────┴─────────────────────────┐  ┌─────────────┴───────────────┐
│      Engine Worker Thread       │  │     Output Worker Thread    │
│  ┌──────────────────────────┐  │  │  ┌───────────────────────┐  │
│  │   PortAudio Callbacks    │  │  │  │   uinput Keyboard     │  │
│  │   (25ms chunks, 40Hz)    │  │  │  │   Simulation          │  │
│  └────────────┬─────────────┘  │  │  └───────────────────────┘  │
│               ▼                 │  │                             │
│  ┌──────────────────────────┐  │  └─────────────────────────────┘
│  │  Threshold Detection     │  │
│  │  (adaptive noise floor)  │  │
│  └────────────┬─────────────┘  │
│               ▼                 │
│  ┌──────────────────────────┐  │
│  │  Vosk Recognition        │  │
│  │  (or coprocess engine)   │  │
│  └──────────────────────────┘  │
└─────────────────────────────────┘
```

**Data Flow:**
1. PortAudio delivers 25ms audio chunks directly to engine worker
2. Worker performs threshold detection and Vosk processing
3. Recognition results sent to main thread for GEC
4. Processed text sent to output worker for typing
5. UI updates throttled to 5Hz to reduce overhead

### Speech Recognition

#### Vosk Engine Integration
- Model path: `/home/john/Downloads/vosk-model-en-us-0.22-lgraph`
- Real-time streaming with partial results
- Configurable beam search parameters
- Confidence-based filtering

#### Configuration Parameters
- `vosk_max_alternatives`: Number of alternative results (0-5)
- `vosk_beam`: Beam search width (5-50)
- `vosk_lattice_beam`: Lattice beam width (1-20)
- `confidence_threshold`: Minimum confidence for output (0-400)

## Usage

### Command Line Interface

```bash
# Basic usage
cd tcl && ./talkie.tcl           # Launch Tcl version
```

### External Control

State can be controlled externally by modifying `~/.talkie`:
```bash
# Enable transcription
echo '{"transcribing": true}' > ~/.talkie

# Disable transcription
echo '{"transcribing": false}' > ~/.talkie
```

### Voice Commands

#### Punctuation Commands
- "period" → "."
- "comma" → ","
- "question mark" → "?"
- "exclamation mark" → "!"
- "colon" → ":"
- "semicolon" → ";"
- "new line" → "\n"
- "new paragraph" → "\n\n"

#### Confidence Filtering
- **Real-time Display**: Shows current confidence score in UI
- **Configurable Threshold**: Adjustable via GUI slider (0-400 range)
- **Noise Reduction**: Filters out low-confidence artifacts

### GUI Features

#### Main Interface
- **Transcription Toggle**: Start/Stop button with color feedback
  - Red: "Start Transcription" (stopped state)
  - Green: "Stop Transcription" (running state)
- **View Switching**: Controls and Text view tabs
- **Real-time Displays**: Audio energy and confidence levels
- **Parameter Controls**: Sliders for all configuration options

#### Configuration Controls
- **Audio Device**: Dropdown selection with refresh
- **Energy Threshold**: Voice activity detection (0-100)
- **Silence Duration**: Trailing silence timeout (0.1-2.0s)
- **Confidence Threshold**: Recognition quality filter (0-400)
- **Vosk Parameters**: Beam search and alternatives tuning
- **Lookback Seconds**: Pre-speech audio buffer (0.1-3.0s)

### Configuration

#### Default Settings
```json
{
    "sample_rate": 44100,
    "frames_per_buffer": 4410,
    "energy_threshold": 5.0,
    "confidence_threshold": 200.0,
    "window_x": 100,
    "window_y": 100,
    "device": "pulse",
    "model_path": "/home/john/Downloads/vosk-model-en-us-0.22-lgraph",
    "silence_trailing_duration": 0.5,
    "lookback_seconds": 1.0,
    "vosk_max_alternatives": 0,
    "vosk_beam": 20,
    "vosk_lattice_beam": 8
}
```

### Dependencies

#### Tcl Packages
- **Tk**: GUI framework
- **Thread**: Worker thread management
- **json**: JSON parsing/generation
- **jbr::unix**: Unix utilities (`cat`, `echo`)
- **jbr::filewatch**: File monitoring
- **pa**: PortAudio bindings (critcl)
- **vosk**: Vosk speech recognition bindings (critcl)
- **audio**: Audio energy calculation (critcl)
- **uinput**: Keyboard simulation (critcl)

#### System Requirements
- Tcl/Tk 8.6+
- PulseAudio or ALSA audio system
- uinput kernel module for keyboard simulation
- Vosk model files

## Development

### Architecture Principles
- **Minimal Code**: Prefer one-liners over bloated functions
- **Trace-Based**: Use variable traces for state synchronization
- **Worker Threads**: Audio and output on dedicated threads (worker.tcl)
- **Async Communication**: `thread::send -async` for cross-thread messaging
- **Global State**: Central `::transcribing` variable for simplicity
- **File-Based IPC**: JSON state files for external control

### Testing
```bash
cd tcl
./talkie.tcl                     # Launch application
```

### Adding Features
1. **State Changes**: Modify `::transcribing` trace handlers
2. **GUI Updates**: Add to existing trace callbacks
3. **Configuration**: Add to `config` array with auto-save trace
4. **External Control**: Leverage existing file watcher system

## Performance

### Audio Processing
- **Sample Rate**: 16kHz (device native rate)
- **Chunk Size**: 25ms (~400 frames at 16kHz)
- **Callback Rate**: 40Hz on engine worker thread
- **Latency**: ~50-100ms speech detection response
- **Lookback**: Configurable pre-speech audio buffering (default 1.0s)

### Threading Benefits
- **No Main Thread Blocking**: Audio processing on dedicated worker
- **Reduced Latency**: Direct path from audio to recognition
- **UI Responsiveness**: GUI never waits for audio processing
- **Throttled Updates**: UI refreshes at 5Hz, not 40Hz

### Real-time Features
- **Energy Display**: Audio level visualization (5Hz updates)
- **Confidence Display**: Recognition quality indicator
- **Partial Results**: Streaming transcription preview
- **State Sync**: 500ms file watcher for external control

## Hardware Support

### Tested Platforms
- Intel Core Ultra 7 155H (primary development)
- Ubuntu Linux 22.04+ with PulseAudio
- Void Linux with PipeWire/PulseAudio
- Various USB and integrated microphones

### Void Linux Setup

The uinput device requires permission setup on Void Linux:

```bash
# Quick fix (temporary, resets on reboot)
make fix-uinput

# Permanent fix: install runit service
make install-uinput-service
```

The runit service (`etc/sv/uinput-perms`) waits for `/dev/uinput` to appear
and sets `group=input mode=660` permissions.

### Audio Devices
- Automatic device detection and selection
- Configurable device selection via GUI
- PulseAudio and ALSA support

## Vosk Model Data

### Model Directories

```
models/vosk/
├── vosk-model-en-us-0.22-lgraph/  # Base model (symlink to ~/Downloads/...)
│   ├── am/                        # Acoustic model
│   ├── conf/                      # Configuration
│   ├── graph/                     # Decoding graph
│   │   ├── words.txt             # Vocabulary
│   │   ├── Gr.fst                # Language model FST
│   │   └── HCLr.fst              # Lexicon/acoustic FST
│   └── ivector/                   # Speaker adaptation
│
└── lm-test/                       # Custom model with domain words
    ├── (same structure as base)
    └── lgraph-base.arpa           # ARPA LM for word probabilities
```

### External Data Files

These files are from the Vosk compile package (not the runtime model):

| File | Location | Purpose |
|------|----------|---------|
| en.dic | `~/Downloads/vosk-model-en-us-0.22-compile/db/en.dic` | Pronunciation dictionary (312k words) |
| en.fst | `~/Downloads/vosk-model-en-us-0.22-compile/db/en-g2p/en.fst` | G2P model for new words |

### POS Disambiguation Data

The POS module (`src/pos_disambiguate.py`) uses:
- **Pronunciation dictionary**: en.dic from compile package
- **Vocabulary**: words.txt from active model (lm-test)
- **Word probabilities**: lgraph-base.arpa from lm-test

Homophone index is cached in `~/.cache/talkie/homophones_*.json`.

### Building Custom Models

See `tools/BUILD-CUSTOM-LGRAPH.md` for instructions on:
- Adding domain vocabulary
- Vocabulary pruning (removes words not in LM)
- Building on GPU host with Kaldi container

