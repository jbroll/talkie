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

### File Structure (Updated August 30, 2025)
```
talkie/
├── talkie.py                          # Main application with OpenVINO integration
├── talkie-with-engine.py              # Reference implementation 
├── JSONFileMonitor.py                 # File watcher for state management
├── launch_talkie.sh                   # New unified launcher
├── verify_npu.py                      # NPU verification tool
├── test_engines.py                    # Engine testing framework
├── requirements.txt                   # Updated with OpenVINO dependencies
└── speech/
    ├── __init__.py                    # Python package marker
    ├── speech_engine.py               # Base classes and factory
    ├── OpenVINO_Whisper_engine.py     # OpenVINO Whisper adapter
    ├── Vosk_engine.py                 # Vosk adapter
    └── FasterWhisper_engine.py        # FasterWhisper adapter
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

## 🚀 Final Deployment Status - COMPLETE SUCCESS

### 🎯 OpenVINO Integration Status (August 30, 2025) - REALISTIC ASSESSMENT:

**✅ CONFIRMED WORKING:**
1. **Hardware**: Intel Core Ultra 7 155H + Intel Arc Graphics (iGPU) + NPU drivers loaded
2. **OpenVINO Stack**: openvino 2025.2.0 + openvino-genai + optimum-intel installed
3. **Model Conversion**: optimum-cli successfully converting Whisper models to OpenVINO format
4. **Intel Arc iGPU**: OpenVINO Whisper initializes successfully on Intel Arc iGPU (~8 sec)
5. **Engine Selection**: Auto-detects available devices and selects appropriately
6. **Fallback System**: Graceful degradation to Vosk when needed

**🔍 HARDWARE DETECTION FINDINGS:**
- ✅ **CPU**: Intel Core Ultra 7 155H (detected)  
- ✅ **iGPU**: Intel Arc Graphics [0x7d55] (detected and working with OpenVINO)
- ❌ **NPU**: intel_vpu driver loaded but not exposed to OpenVINO 2025.2.0 (needs investigation)

**📊 PERFORMANCE MEASURED:**
- Intel Arc iGPU initialization: ~8 seconds
- Model conversion (one-time): varies by model size  
- Vosk fallback: <1 second initialization

### 📋 Current Deployment Modes:

**🔧 Current System (Intel Core Ultra + Arc iGPU)**:
- Command: `source bin/activate && ./launch_talkie.sh`
- Behavior: Auto-detects Intel Arc iGPU → uses OpenVINO Whisper → Vosk fallback available
- Status: **FUNCTIONAL WITH INTEL ARC iGPU ACCELERATION** ⚡

**⚡ Future NPU Support**:
- Hardware: Intel Core Ultra 7 155H has NPU (intel_vpu driver loaded)
- Issue: OpenVINO 2025.2.0 not exposing NPU device (driver compatibility)
- Status: **FRAMEWORK READY** - needs OpenVINO NPU plugin or newer version

**🛠️ Manual Engine Selection**:
- Force OpenVINO: `python talkie.py --engine openvino --ov-device GPU`
- Force Vosk: `python talkie.py --engine vosk`
- Force Auto: `python talkie.py --engine auto` (default)

### 🔍 Verified Working Commands:
- **✅ NPU/OpenVINO Check**: `python verify_npu.py` - Shows all packages installed
- **✅ Live OpenVINO Demo**: `./launch_talkie.sh --verbose` - **NOW USES OPENVINO GPU** 🚀
- **✅ Force CPU**: `python talkie.py --engine openvino --ov-device CPU --whisper-model openai/whisper-tiny`
- **✅ Force GPU**: `python talkie.py --engine openvino --ov-device GPU` 
- **✅ Force Vosk**: `python talkie.py --engine vosk` (fallback working)

### 🎯 Performance Status:
- **OpenVINO GPU**: Model conversion ~30 seconds, then real-time speech recognition ⚡
- **OpenVINO CPU**: Model conversion ~30 seconds, then real-time speech recognition
- **Vosk Fallback**: Instant startup, reliable speech recognition backup