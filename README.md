# Talkie - Modular Speech-to-Text for Ubuntu Linux

<img src="Screenshot%20from%202025-09-07%2015-22-01.png" alt="Talkie UI" align="right" width="500"/>

A modular speech-to-text application designed for seamless Ubuntu Linux integration. Talkie provides real-time audio transcription with intelligent keyboard simulation, featuring a modern GUI with bubble mode, configurable audio processing, and support for multiple speech recognition engines.

<br clear="right"/>

## Features

### Core Capabilities
- **Real-time Speech Recognition**: Continuous audio processing with immediate transcription
- **Multiple Speech Engines**: Vosk (primary) and Sherpa-ONNX (fallback) with automatic detection
- **Intelligent Text Processing**: Voice command punctuation and word-to-number conversion
- **Direct Keyboard Integration**: Text insertion into any focused application via uinput
- **Modern GUI**: Standard and bubble mode interfaces with persistent configuration

### Advanced Features  
- **Voice Activity Detection**: Configurable thresholds with pre-speech audio buffering
- **Confidence Filtering**: Post-processing confidence filtering for improved transcription quality
- **Configurable Audio Pipeline**: Adjustable sample rates, block duration, and silence handling
- **State Management**: Persistent configuration and external control via JSON state files
- **Desktop Integration**: Global hotkeys and background operation support

## Quick Start

### Installation

```bash
# Clone and enter directory
cd /home/john/src/talkie

# Install dependencies (virtual environment detected automatically)
pip install -r requirements.txt

# Run the application
./talkie.sh
```

### Basic Usage

```bash
# Launch with GUI
./talkie.sh

# Transcription control
./talkie.sh start                   # Enable transcription
./talkie.sh stop                    # Disable transcription  
./talkie.sh toggle                  # Toggle transcription state
./talkie.sh state                   # Show current state

# Start with transcription enabled
./talkie.sh --transcribe
```

### Advanced Usage

```bash
# Engine selection
./talkie.sh --engine auto           # Auto-detect (default: Vosk)
./talkie.sh --engine vosk           # Force Vosk engine
./talkie.sh --engine sherpa-onnx    # Force Sherpa-ONNX

# Audio device selection
./talkie.sh --device "USB"          # Select device by name substring
./talkie.sh --verbose               # Enable debug logging

# Direct Python execution
python3 talkie.py --help            # See all options
```

## Architecture

### Modular Design

The application uses a clean modular architecture with separated concerns:

```
talkie/
├── talkie.py                    # Main application orchestrator
├── audio_manager.py             # Audio processing and device management
├── gui_manager.py               # Tkinter GUI with bubble mode
├── config_manager.py            # Configuration persistence  
├── text_processor.py            # Text processing and punctuation
├── keyboard_simulator.py        # Keyboard input simulation
├── talkie.sh                    # Shell launcher with state management
└── speech/                      # Speech recognition engines
    ├── speech_engine.py         # Base classes and factory
    ├── Vosk_engine.py           # Vosk adapter
    └── SherpaONNX_engine.py     # Sherpa-ONNX adapter
```

### Core Components

#### TalkieApplication (talkie.py)
Main orchestrator coordinating all components, handling engine configuration, audio device setup, and threading coordination.

#### AudioManager (audio_manager.py) 
Manages audio input with voice activity detection, configurable thresholds, circular buffering for pre-speech audio, and silence/timeout handling.

#### TalkieGUI (gui_manager.py)
Modern Tkinter interface supporting both standard and bubble modes, real-time transcription display, audio device selection, and persistent window positioning.

#### TextProcessor (text_processor.py)
Intelligent text processing with voice command punctuation mapping, number word-to-digit conversion, and processing state management.

#### ConfigManager (config_manager.py)
JSON-based configuration persistence with runtime parameter updates and window position management.

#### KeyboardSimulator (keyboard_simulator.py)
Direct keyboard input simulation via uinput for real-time text insertion into any application.

### Speech Recognition Engines

Uses adapter pattern with factory-based instantiation:

- **Vosk Engine**: CPU-based recognition with high accuracy, real-time streaming
- **Sherpa-ONNX Engine**: Optimized CPU implementation with INT8 quantization  
- **Automatic Detection**: Intelligent engine selection with graceful fallback
- **Confidence Scoring**: Real-time confidence assessment with configurable filtering thresholds

## Voice Commands

### Punctuation Commands
- "period" → "."
- "comma" → ","
- "question mark" → "?"  
- "exclamation mark" → "!"
- "colon" → ":"
- "semicolon" → ";"
- "new line" → "\\n"
- "new paragraph" → "\\n\\n"

### Number Processing
- Automatic word-to-number conversion using word2number
- Timeout-based number sequence finalization
- State-based processing for complex numbers

## GUI Features

### Standard Mode
- Transcription control toggle with visual feedback
- Audio device selection dropdown
- Real-time energy level and confidence score display
- Partial transcription result preview
- Confidence filtering with adjustable thresholds
- Configuration parameter adjustment

### Bubble Mode
- Minimized floating window interface
- Persistent positioning across sessions
- Configurable silence timeout
- Quick transcription toggle

## Configuration

### Default Settings
Configuration is stored in `~/.talkie.conf`:

```json
{
    "audio_device": "pulse",
    "energy_threshold": 50.0,
    "silence_trailing_duration": 0.5,
    "speech_timeout": 3.0,
    "lookback_frames": 10,
    "engine": "vosk",
    "model_path": "/home/john/Downloads/vosk-model-en-us-0.22-lgraph",
    "window_x": 100,
    "window_y": 100,
    "bubble_enabled": false,
    "bubble_silence_timeout": 3.0,
    "vosk_max_alternatives": 0,
    "vosk_beam": 20,
    "vosk_lattice_beam": 8,
    "confidence_threshold": 280.0
}
```

### State Management
- **`~/.talkie`**: Transcription state JSON (`{"transcribing": true/false}`)
- **JSONFileMonitor**: Real-time state change detection
- **External Control**: Shell commands update state file automatically

## Technical Specifications

### Audio Pipeline
1. **Capture**: sounddevice input stream (16kHz, 0.1s blocks)
2. **Detection**: Voice activity detection with energy thresholds  
3. **Buffering**: Circular buffer for pre-speech audio lookback (5 frames)
4. **Processing**: Real-time speech recognition with partial results
5. **Output**: Direct keyboard simulation via uinput

### Performance
- **Latency**: Sub-second response times
- **Sample Rate**: 16kHz with automatic device rate conversion
- **Memory Usage**: Optimized for continuous operation
- **Threading**: Separate GUI and transcription threads for responsiveness

### Hardware Requirements
- **OS**: Ubuntu Linux 22.04+ with PulseAudio/ALSA
- **Python**: 3.8+ with virtual environment support
- **Audio**: Microphone input capability
- **System**: uinput kernel module for keyboard simulation
- **CPU**: Tested on Intel Core Ultra 7 155H

## Dependencies

Core requirements from `requirements.txt`:
```
sounddevice      # Audio capture
vosk             # Primary speech recognition
sherpa-onnx      # Alternative speech engine
word2number      # Number word conversion
numpy            # Audio data processing
```

System requirements:
- Tkinter (usually included with Python)
- uinput kernel module
- PulseAudio or ALSA

## Development

### Testing Tools
```bash
python3 test_speech_engines.py     # Test available engines
python3 test_modular.py             # Test modular components
```

### Debugging
```bash
./talkie.sh --verbose               # Enable debug logging
python3 talkie.py -v                # Direct execution with verbose output
```

### Adding New Speech Engines
1. Implement `SpeechEngine` abstract class in `speech/` directory
2. Register with `SpeechEngineFactory` 
3. Add engine type to `SpeechEngineType` enum
4. Update CLI arguments and detection logic

### Integration Points
- **Global Hotkeys**: Meta+E toggle transcription
- **External Control**: JSON state file for programmatic control
- **Desktop Integration**: Works with all applications via keyboard simulation
- **Background Operation**: Can run as system service

## License

This project is designed for Ubuntu Linux integration and follows standard open-source practices.
