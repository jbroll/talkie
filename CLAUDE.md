# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Talkie is a speech-to-text program designed for Ubuntu Linux that provides seamless audio integration. It captures audio input, performs speech-to-text transcription, and outputs text to the currently focused window using keyboard simulation.

## Commands

### Running the Application (Updated August 30, 2025)
- `./launch_talkie.sh` - New unified launcher with automatic engine detection
- `python3 talkie.py` - Main application with OpenVINO Whisper integration
  - `--engine auto|vosk|openvino` - Force specific engine (default: auto)
  - `--whisper-model MODEL` - Specify OpenVINO Whisper model (default: openai/whisper-base)
  - `--ov-device AUTO|NPU|GPU|CPU` - OpenVINO device selection (default: AUTO)
- `./talkie.sh` - Shell wrapper with control commands (legacy):
  - `./talkie.sh start` - Start transcription
  - `./talkie.sh stop` - Stop transcription  
  - `./talkie.sh toggle` - Toggle transcription on/off
  - `./talkie.sh state` - Show current transcription state

### Dependencies
- Install dependencies: `pip install -r requirements.txt` (now includes OpenVINO packages)
- Uses Python virtual environment (pyvenv.cfg present)

### Validation Tools (New)
- `python3 verify_npu.py` - Check NPU and OpenVINO requirements
- `python3 test_engines.py` - Test available speech engines

### State Management
The application uses `~/.talkie` JSON file to track transcription state. The JSONFileMonitor.py watches for changes to this file to control the transcription process.

## Architecture

### Core Components
- **talkie.py**: Main application with GUI (Tkinter) and speech processing
- **talkie-with-engine.py**: Alternative implementation with pluggable speech engines
- **JSONFileMonitor.py**: File watcher for state management
- **speech/**: Directory containing speech engine implementations

### Speech Engine Architecture (Updated August 30, 2025)
The project uses an adapter pattern for speech engines:
- **speech/speech_engine.py**: Base SpeechEngine abstract class and SpeechResult format (renamed from hyphenated file)
- **speech/Vosk_engine.py**: Vosk speech recognition implementation (renamed)
- **speech/FasterWhisper_engine.py**: FasterWhisper implementation (renamed)
- **speech/OpenVINO_Whisper_engine.py**: Intel OpenVINO Whisper implementation (renamed from VINOWisper.py)

### Key Architecture Changes (August 30, 2025)
- **Unified Engine Interface**: All speech engines now use the SpeechManager pattern
- **Automatic Engine Detection**: System automatically detects NPU availability and selects best engine
- **Python Naming Convention**: All files renamed from hyphens to underscores for proper Python imports
- **Enhanced CLI**: Command-line arguments for engine and model selection
- **Validation Framework**: Comprehensive testing and verification tools

### Key Features
- Multiple speech recognition backends (Vosk, Whisper variants)
- Real-time audio processing with configurable block duration (0.1s default)
- Number word-to-digit conversion using word2number
- Keyboard input simulation via uinput
- GUI with text preview and correction capabilities
- State-based processing (NORMAL/NUMBER modes)

### Configuration
- Default model path: `/home/john/Downloads/vosk-model-en-us-0.22-lgraph`
- Audio block duration: 0.1 seconds
- Queue size: 5 blocks
- Uses 16kHz sample rate for audio processing

### File Structure (Updated August 31, 2025)
```
talkie/
├── talkie.py                          # Main application with CPU speech engines
├── talkie.sh                          # Unified shell launcher
├── JSONFileMonitor.py                 # File watcher for state management
├── test_speech_engines.py             # Comprehensive engine testing
├── requirements.txt                   # Clean CPU-only dependencies
└── speech/
    ├── __init__.py                    # Python package marker  
    ├── speech_engine.py               # Base classes and factory
    ├── SherpaONNX_engine.py           # Sherpa-ONNX CPU adapter
    └── Vosk_engine.py                 # Vosk adapter
```

## Implementation Status (August 30, 2025)

### ✅ Completed:
1. File naming standardization (hyphens → underscores)
2. OpenVINO Whisper integration framework
3. Automatic engine detection and fallback
4. Enhanced CLI with engine selection
5. NPU verification and testing tools
6. Updated dependencies and documentation

### ✅ Successfully Resolved (Session Continued):
1. **Adapter Registration**: Fixed direct instantiation in SpeechManager instead of factory pattern
2. **Virtual Environment**: Properly activated and tested with existing dependencies (vosk available)
3. **Engine Testing**: Both Vosk and OpenVINO engines tested and working as expected
4. **Integration Testing**: Complete workflow validated end-to-end

### 🎯 Final Status - MIGRATION COMPLETE ✅:
1. ✅ **Engine Detection**: Auto-detects NPU availability and falls back to Vosk correctly
2. ✅ **Vosk Integration**: Successfully initializes and integrates with speech manager pattern
3. ✅ **OpenVINO Framework**: Complete framework ready for NPU deployment
4. ✅ **CLI Interface**: Full command-line interface with engine selection working
5. ✅ **Launcher Script**: Unified launcher script with automatic detection working
6. ✅ **File Structure**: All files properly renamed and structured for Python imports

## Current Status (August 31, 2025)

### Vosk Primary Engine Integration Complete

**Working Components:**
- Intel Core Ultra 7 155H with reliable CPU processing
- Vosk speech recognition with proven accuracy and reliability
- CPU-based speech recognition with excellent quality and performance
- Automatic engine detection and fallback system

**Current Implementation:**
- **Primary:** Vosk (optimized for accuracy and reliability)
- **Fallback:** Sherpa-ONNX CPU (if Vosk unavailable)
- Clean, simplified codebase focused on accuracy

### Command Reference

**Primary Usage:**
```bash
./talkie.sh                    # Run with Vosk engine (default)
./talkie.sh start              # Start transcription
./talkie.sh stop               # Stop transcription
./talkie.sh toggle             # Toggle transcription
./talkie.sh state              # Show current state
```

**Engine Selection:**
```bash
./talkie.sh --engine auto              # Auto-detect (default: Vosk)
./talkie.sh --engine vosk              # Force Vosk (recommended)
./talkie.sh --engine sherpa-onnx       # Force Sherpa-ONNX CPU
```

### Intel ARC Graphics Integration Process (Reference)

**Note:** The following documents the successful ARC Graphics GPU acceleration process that was implemented and tested. While removed from the current codebase for simplicity, this process can be referenced for future GPU integration work.

**Successfully Validated Hardware:**
- Intel Core Ultra 7 155H with Intel Arc Graphics [0x7d55]
- OpenVINO 2025.2.0 stack with GPU acceleration
- Sherpa-ONNX built from source with onnxruntime-openvino integration

**Achieved Performance Metrics:**
- Sherpa-ONNX GPU: 3.45s for 6.6s audio (1.91x real-time performance)
- GPU acceleration successfully implemented and tested

**Integration Steps (Reference):**
1. **Environment Setup:** LD_LIBRARY_PATH, ORT_PROVIDERS, OV_DEVICE configuration
2. **OpenVINO Detection:** GPU device availability checking
3. **Sherpa-ONNX Configuration:** Provider selection and model loading
4. **Runtime Optimization:** INT8 quantization with OpenVINO execution

**Key Files for Future GPU Work:**
- Environment variable management in main application
- Provider selection logic in speech engine adapters
- OpenVINO device detection and configuration
- Performance benchmarking and validation tools

### When generating replies, documentation, or code:

- Use a concise, professional, technical style.
- Provide complete and detailed documentation that fully explains the subject.
- Include helpful examples where needed, but avoid excess or repetition.
- Do not include marketing language, self-promotion, or filler text.
- Avoid analogies, rhetorical questions, or conversational flourishes.
- No emojis, decorative symbols, or casual expressions.
- Use plain Markdown for structure: headings, lists, code blocks.
- Keep examples minimal, relevant, and focused.
- Prioritize correctness, clarity, and reproducibility.
- Assume the audience has a technical background.
- Eliminate speculation and irrelevant details.
