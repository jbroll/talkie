# Coprocess Speech Engine Architecture

## Overview

All speech engines (except Vosk legacy) now use a unified coprocess architecture with a shared base class to eliminate code duplication.

## Architecture Diagram

```
Talkie (Tcl)
    ↓
engine.tcl (Registry + Type Dispatch)
    ↓
coprocess.tcl (IPC Manager)
    ↓
[Python Engine Process]
    ↓
speech_engine_base.py (Base Class)
    ↓
    ├─→ faster_whisper_engine.py (Whisper-specific)
    └─→ sherpa_engine.py (Sherpa-ONNX-specific)
```

## Base Class (`speech_engine_base.py`)

### Responsibilities:
- **Audio buffering**: Accumulates int16 PCM audio
- **Command protocol**: PROCESS, FINAL, RESET, MODEL
- **Sample rate handling**: Converts any input to 16kHz
- **PyAV resampling**: High-quality FFmpeg resampling
- **Vosk-format responses**: JSON compatibility layer
- **Binary I/O**: Proper stdin/stdout handling

### Interface for Subclasses:

```python
class SpeechEngineBase:
    def load_model(self, model_path) -> bool:
        """Load recognition model (implemented by subclass)"""
        raise NotImplementedError

    def transcribe_audio(self, audio) -> (text, confidence):
        """Transcribe 16kHz float32 audio (implemented by subclass)"""
        raise NotImplementedError
```

## Engine Implementations

### 1. Faster-Whisper (`faster_whisper_engine.py`)

**Lines of code**: 120 (vs 254 before base class)

**Implements**:
- `load_model()`: WhisperModel initialization
- `transcribe_audio()`: Segment-based transcription
- **Confidence mapping**: logprob → Vosk scale (0-1000)

**Model files**: Single directory with model files

**Confidence algorithm**:
```python
logprob >= -0.5:  conf = 900-1000  # Excellent
logprob >= -1.0:  conf = 700-900   # Good
logprob >= -2.0:  conf = 300-700   # Fair
logprob <  -2.0:  conf = 0-300     # Poor
```

### 2. Sherpa-ONNX (`sherpa_engine.py`)

**Lines of code**: ~140 (new coprocess implementation)

**Implements**:
- `load_model()`: Sherpa streaming recognizer
- `transcribe_audio()`: Stream-based processing
- **Confidence estimation**: Word count heuristic

**Model files**: 4 ONNX files + tokens.txt
- encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx
- decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx
- joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx
- tokens.txt

**Confidence algorithm**:
```python
word_count == 0:   conf = 0
word_count >= 10:  conf = 900
word_count 1-9:    conf = 500 + (count-1) * 44
```

### 3. Vosk (Legacy - `vosk.tcl`)

**Type**: critcl (in-process binding)
**Remains unchanged** - still uses Tcl critcl wrapper

## Engine Registry (`engine.tcl`)

```tcl
array set engine_registry {
    vosk,type         "critcl"
    vosk,command      "python3 engines/vosk_engine.py"
    vosk,model_dir    "vosk"

    sherpa,type       "coprocess"
    sherpa,command    "engines/sherpa_wrapper.sh"
    sherpa,model_dir  "sherpa-onnx"

    faster-whisper,type    "coprocess"
    faster-whisper,command "engines/faster_whisper_wrapper.sh"
    faster-whisper,model_dir "faster-whisper"
}
```

## Protocol (Coprocess Engines)

### Commands (stdin - text):
```
PROCESS byte_count    # Followed by binary audio data
FINAL                 # Get transcription and clear buffer
RESET                 # Clear buffer without transcribing
MODEL /path           # Load different model
```

### Responses (stdout - JSON):
```json
{"partial": ""}                                          // PROCESS response
{"alternatives": [{"text": "...", "confidence": 850}]}  // FINAL response
{"status": "ok"}                                         // Command success
{"error": "message"}                                     // Error
```

### Startup message:
```json
{"status": "ok", "engine": "faster-whisper", "version": "1.0", "sample_rate": 44100}
```

## Sample Rate Handling

**Problem**: Whisper/Sherpa require 16kHz, devices typically use 44.1kHz

**Solution**: Base class automatically resamples using PyAV

```python
def resample_audio(self, audio, orig_sr=44100, target_sr=16000):
    # Uses FFmpeg's libswresample (high quality, ~1.4ms/sec)
    # Proper anti-aliasing filter
    # Returns float32 array at 16kHz
```

## Code Reuse Statistics

### Before Base Class:
- faster_whisper_engine.py: 254 lines
- (Sherpa was in-process Tcl, not comparable)

### After Base Class:
- speech_engine_base.py: 230 lines (shared)
- faster_whisper_engine.py: 120 lines (50% reduction)
- sherpa_engine.py: 140 lines (new, but minimal)

**Total lines saved**: ~200 lines
**Shared functionality**: ~230 lines now reusable

## Adding New Engines

To add a new coprocess engine:

1. **Create engine file** (`engines/my_engine.py`):
```python
from speech_engine_base import SpeechEngineBase

class MyEngine(SpeechEngineBase):
    def __init__(self, model_path, sample_rate):
        super().__init__(model_path, sample_rate, "my-engine", "1.0")

    def load_model(self, model_path):
        # Load your model
        self.model = load_my_model(model_path)
        return True

    def transcribe_audio(self, audio):
        # Transcribe 16kHz float32 audio
        text = self.model.transcribe(audio)
        confidence = 850  # Your confidence metric
        return text, confidence

def main():
    # Standard boilerplate
    engine = MyEngine(sys.argv[1], sys.argv[2])
    engine.send_startup_message()
    engine.run()
```

2. **Create wrapper script** (`engines/my_wrapper.sh`):
```bash
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"
source "$PROJECT_DIR/venv/bin/activate"
exec python3 "$SCRIPT_DIR/my_engine.py" "$@"
```

3. **Register in engine.tcl**:
```tcl
my-engine,type         "coprocess"
my-engine,command      "engines/my_wrapper.sh"
my-engine,model_dir    "my-models"
my-engine,model_config "my_modelfile"
```

4. **Add to UI** (`ui-layout.tcl`):
```tcl
set ::speech_engines {vosk sherpa faster-whisper my-engine}
```

That's it! Base class handles:
- ✓ Audio buffering
- ✓ Protocol implementation
- ✓ Resampling
- ✓ JSON formatting
- ✓ Error handling

## Benefits

### Maintainability:
- Bug fixes in one place benefit all engines
- Protocol changes only touch base class
- Consistent behavior across engines

### Performance:
- PyAV resampling: 1.4ms/sec (excellent quality)
- Shared code path (optimized once)
- Minimal per-engine overhead

### Flexibility:
- Easy to add new engines
- Can override base methods if needed
- Mix-and-match: some coprocess, some critcl

## Migration Path

**Old** (Sherpa was critcl):
- sherpa.tcl: 118 lines of Tcl wrapper code
- Critcl bindings: Complex Vosk-format conversion
- In-process: Crashes affect Talkie

**New** (Sherpa is coprocess):
- sherpa_engine.py: 140 lines, inherits 230 from base
- Clean Python API
- Out-of-process: Crash isolated

**Vosk remains critcl** for backward compatibility.

## Dependencies

All coprocess engines share:
- PyAV (already required by faster-whisper)
- numpy (already required by all ML engines)

No additional dependencies needed!

## Status

✅ **Architecture Complete**
- Base class implemented and tested
- Faster-Whisper refactored
- Sherpa-ONNX migrated to coprocess
- All three engines registered and working

## Testing

```bash
# Test through Talkie GUI
cd /home/john/src/talkie/src
./talkie.tcl

# Switch engines in Config dialog
# All three should work identically from UI perspective
```
