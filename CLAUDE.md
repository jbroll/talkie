# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Talkie is a modular speech-to-text application designed for Ubuntu Linux. It provides real-time audio transcription with intelligent keyboard simulation, featuring a modern GUI with bubble mode, configurable audio processing, and support for multiple speech recognition engines.

## Architecture

### Modular Design (September 2025)

The application has been completely refactored into a modular architecture:

```
talkie/
├── talkie.py                    # Main application orchestrator
├── audio_manager.py             # Audio processing and device management
├── gui_manager.py               # Tkinter GUI with bubble mode
├── config_manager.py            # Configuration persistence
├── text_processor.py            # Text processing and punctuation
├── keyboard_simulator.py        # Keyboard input simulation
├── talkie.sh                    # Shell launcher with state management
├── requirements.txt             # Dependencies
├── JSONFileMonitor.py           # State file monitoring
└── speech/                      # Speech recognition engines
    ├── __init__.py              # Package initialization
    ├── speech_engine.py         # Base classes and factory
    ├── Vosk_engine.py           # Vosk adapter
    └── SherpaONNX_engine.py     # Sherpa-ONNX adapter
```

### Core Components

#### TalkieApplication (talkie.py)
Main application orchestrator that coordinates all components:
- Component initialization and lifecycle management
- Engine configuration and fallback logic
- Audio device setup and management
- Threading coordination for GUI and transcription
- Signal handling and cleanup

#### AudioManager (audio_manager.py)
Manages audio input and voice activity detection:
- Audio device selection and configuration
- Voice activity detection with configurable thresholds
- Circular buffer for pre-speech audio lookback
- Silence trailing and speech timeout handling
- Integration with JSONFileMonitor for state changes

#### TalkieGUI (gui_manager.py)
Tkinter-based GUI interface:
- Standard window and bubble mode interfaces
- Real-time transcription display with partial results
- Audio device selection dropdown
- Configurable voice threshold and timeouts
- Persistent window positioning and configuration
- Energy level visualization

#### TextProcessor (text_processor.py)
Intelligent text processing and formatting:
- Voice command punctuation mapping
- Number word-to-digit conversion using word2number
- Processing state management (NORMAL/NUMBER modes)
- Timeout handling for number sequences
- Keyboard output coordination

#### ConfigManager (config_manager.py)
Configuration persistence and management:
- JSON-based configuration storage in `~/.talkie.conf`
- Default configuration with sensible values
- Runtime parameter updates and persistence
- Window position and state management

#### KeyboardSimulator (keyboard_simulator.py)  
Direct keyboard input simulation via uinput:
- Real-time text insertion into focused applications
- Virtual keyboard device creation and management
- Unicode text support with proper encoding

### Speech Recognition Engines

#### Engine Architecture
Uses adapter pattern with factory-based instantiation:
- **SpeechEngine**: Abstract base class defining common interface
- **SpeechResult**: Standardized result format with confidence and timing
- **SpeechEngineType**: Enumeration of supported engines
- **SpeechEngineFactory**: Factory for creating engine adapters

#### Supported Engines

1. **Vosk Engine** (Primary)
   - CPU-based recognition with high accuracy
   - Model path: `/home/john/Downloads/vosk-model-en-us-0.22-lgraph`
   - Real-time streaming with partial results
   - Reliable fallback option

2. **Sherpa-ONNX Engine** (Alternative)
   - CPU-optimized implementation
   - INT8 quantization for performance
   - Model path: `models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26`

#### Engine Selection Logic
- **Auto**: Prefers Vosk for accuracy, falls back to Sherpa-ONNX
- **Manual**: Force specific engine via CLI arguments
- **Fallback**: Automatic fallback if primary engine fails

## Usage

### Command Line Interface

```bash
# Basic usage
./talkie.sh                         # Launch with GUI
python3 talkie.py                   # Direct Python execution

# Engine selection
./talkie.sh --engine auto           # Auto-detect (default)
./talkie.sh --engine vosk           # Force Vosk engine
./talkie.sh --engine sherpa-onnx    # Force Sherpa-ONNX

# Audio device
./talkie.sh --device "USB"          # Select device by substring
./talkie.sh --verbose               # Enable debug logging

# Transcription control
./talkie.sh start                   # Enable transcription
./talkie.sh stop                    # Disable transcription
./talkie.sh toggle                  # Toggle transcription state
./talkie.sh state                   # Show current state

# Start with transcription enabled
./talkie.sh --transcribe            # Start transcribing immediately
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

#### Number Processing
- Automatic word-to-number conversion
- Timeout-based number sequence finalization
- State-based processing for complex numbers

### GUI Features

#### Standard Mode
- Transcription control toggle
- Audio device selection
- Real-time energy level display
- Partial result preview
- Configuration parameter adjustment

#### Bubble Mode
- Minimized floating window interface
- Persistent positioning across sessions
- Configurable silence timeout
- Quick transcription toggle

### Configuration

#### Default Settings
```json
{
    "audio_device": "pulse",
    "voice_threshold": 50.0,
    "silence_trailing_duration": 0.5,
    "speech_timeout": 3.0,
    "lookback_frames": 5,
    "engine": "vosk",
    "model_path": "/home/john/Downloads/vosk-model-en-us-0.22-lgraph",
    "window_x": 100,
    "window_y": 100,
    "bubble_enabled": false,
    "bubble_silence_timeout": 3.0
}
```

#### Configuration Files
- **`~/.talkie.conf`**: Main configuration persistence
- **`~/.talkie`**: Transcription state (JSON with `{"transcribing": true/false}`)

### Dependencies

#### Core Requirements (requirements.txt)
```
sounddevice
vosk
word2number
numpy
sherpa-onnx
```

#### System Requirements
- Python 3.8+ with virtual environment
- PulseAudio or ALSA audio system
- uinput kernel module for keyboard simulation
- Tkinter for GUI (usually included with Python)

## Development

### Testing Tools
```bash
python3 test_speech_engines.py     # Test available engines
python3 test_modular.py             # Test modular components
```

### Debugging
```bash
./talkie.sh --verbose               # Enable debug logging
python3 talkie.py -v                # Direct Python with verbose
```

### Adding New Engines
1. Implement `SpeechEngine` abstract class
2. Create adapter in `speech/` directory  
3. Register with `SpeechEngineFactory`
4. Add engine type to `SpeechEngineType` enum
5. Update CLI arguments and detection logic

## Performance

### Audio Processing
- **Sample Rate**: 16kHz
- **Block Duration**: 0.1 seconds (configurable)
- **Queue Size**: 5 blocks
- **Latency**: Sub-second response times
- **Lookback Buffer**: 5 frames for pre-speech audio

### Speech Recognition
- **Vosk**: Real-time CPU processing, high accuracy
- **Sherpa-ONNX**: Optimized CPU implementation with INT8
- **Memory Usage**: Optimized for continuous operation

### GUI Performance  
- **Update Rate**: 100ms UI refresh
- **Energy Display**: Real-time audio level visualization
- **Bubble Mode**: Minimal resource overhead

## Hardware Support

### Tested Platforms
- Intel Core Ultra 7 155H (primary development)
- Ubuntu Linux 22.04+ with PulseAudio
- Various USB and integrated microphones

### Audio Devices
- Automatic device detection and selection
- Configurable device selection by name substring
- Support for multiple sample rates with automatic conversion

## State Management

### Transcription State
- File-based state persistence in `~/.talkie`
- JSONFileMonitor watches for external state changes
- Immediate UI updates on state transitions
- Shell command integration for external control

### Configuration Persistence
- Automatic configuration saving on parameter changes
- Window position persistence across sessions  
- Device selection memory
- Engine preference storage

## Integration

### Desktop Integration
- Global hotkey support (Meta+E toggle)
- Keyboard input simulation works with all applications
- Window focus management for text insertion
- Background operation support

### External Control
- Shell command interface via `talkie.sh`
- JSON state file for programmatic control
- File monitor for real-time state synchronization

## Technical Implementation

### Threading Model
- Main GUI thread for UI responsiveness
- Dedicated transcription thread for audio processing
- Thread-safe communication via queues and callbacks

### Audio Pipeline
1. **Capture**: sounddevice input stream with configurable blocksize
2. **Detection**: Voice activity detection with energy thresholds
3. **Buffering**: Circular buffer for pre-speech audio lookback
4. **Processing**: Real-time speech recognition with partial results
5. **Output**: Direct keyboard simulation via uinput

### Error Handling
- Graceful engine fallback on initialization failure
- Audio device failure recovery
- Comprehensive logging with configurable verbosity
- Clean resource cleanup on application exit