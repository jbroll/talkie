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
├── audio.tcl                    # Audio processing and transcription control
├── gui.tcl                      # Tk UI interface
├── display.tcl                  # Text display and visualization
├── device.tcl                   # Audio device management
├── vosk.tcl                     # Vosk speech engine integration
├── uinput/                      # Keyboard simulation
│   ├── uinput.tcl              # uinput wrapper
│   └── test_uinput_verify.tcl  # Testing tools
├── pa/                          # PortAudio bindings
├── vosk/                        # Vosk bindings
└── audio/                       # Audio processing bindings
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

#### Audio Processing (audio.tcl)
- Real-time audio stream processing via PortAudio
- Voice activity detection with energy thresholds
- Circular buffer for pre-speech audio lookback
- Vosk speech recognition integration
- Global transcription state management

#### GUI Interface (gui.tcl)
- Tk-based responsive interface
- Controls and text view switching
- Real-time audio energy and confidence display
- Automatic button updates via `::transcribing` trace
- Device selection and parameter adjustment

#### Display Management (display.tcl)
- Text output formatting and display
- Partial and final result handling
- Energy level and confidence visualization
- Rolling buffer management

#### Device Management (device.tcl)
- Audio device enumeration and selection
- GUI dropdown population
- Device configuration updates

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
- **json**: JSON parsing/generation
- **jbr::unix**: Unix utilities (`cat`, `echo`)
- **jbr::filewatch**: File monitoring
- **pa**: PortAudio bindings
- **vosk**: Vosk speech recognition bindings
- **audio**: Audio processing utilities
- **uinput**: Keyboard simulation

#### System Requirements
- Tcl/Tk 8.6+
- PulseAudio or ALSA audio system
- uinput kernel module for keyboard simulation
- Vosk model files

## Development

### Architecture Principles
- **Minimal Code**: Prefer one-liners over bloated functions
- **Trace-Based**: Use variable traces for state synchronization
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
- **Sample Rate**: 44.1kHz (configurable)
- **Buffer Size**: 4410 frames (~0.1s at 44.1kHz)
- **Latency**: Sub-second response times
- **Lookback**: Configurable pre-speech audio buffering

### Real-time Features
- **Energy Display**: Live audio level visualization
- **Confidence Display**: Real-time recognition quality
- **Partial Results**: Streaming transcription preview
- **State Sync**: 500ms file watcher updates

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

