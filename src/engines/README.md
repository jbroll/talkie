# Speech Engine Coprocess Protocol

This directory contains speech engine implementations that communicate via a simple text-based protocol over stdin/stdout.

## Protocol

**Commands (stdin):**
- `PROCESS byte_count` + binary audio data
- `FINAL` - Get final transcription result
- `RESET` - Clear audio buffer
- `MODEL model_path` - Load different model

**Responses (stdout):**
- JSON in Vosk format

## Engines

### faster_whisper_engine.py

**Usage:**
```bash
python3 faster_whisper_engine.py model_path sample_rate
```

**Requirements:**
```bash
pip install faster-whisper
```

**Download models:**
```bash
# Download Whisper models
pip install -U huggingface_hub
huggingface-cli download Systran/faster-whisper-base.en --local-dir ~/models/faster-whisper-base.en

# Or use GGML format models
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin -O ~/models/whisper-base.en
```

**Features:**
- Batch processing mode (accumulates audio until FINAL)
- GPU acceleration support (change `device="cpu"` to `device="cuda"`)
- INT8 quantization for speed
- Runtime model switching

**Example:**
```bash
$ python3 faster_whisper_engine.py ~/models/faster-whisper-base.en 16000
{"status": "ok", "engine": "faster-whisper", "version": "1.0", "sample_rate": 16000}

PROCESS 3200
[binary audio data]
{"partial": ""}

FINAL
{"alternatives": [{"text": "hello world", "confidence": 0.95}]}

RESET
{"status": "ok"}
```

## Testing

```bash
cd src
./test_coprocess.tcl
```

## Protocol Details

### PROCESS Command

Sends audio chunk for processing:

```
PROCESS 8820\n
[8820 bytes of int16 PCM audio]
```

Response:
```json
{"partial": "hello world"}
```

### FINAL Command

Get final transcription result and clear buffer:

```
FINAL\n
```

Response:
```json
{
  "alternatives": [
    {"text": "hello world how are you", "confidence": 0.95}
  ]
}
```

### RESET Command

Clear audio buffer:

```
RESET\n
```

Response:
```json
{"status": "ok"}
```

### MODEL Command

Load different model at runtime:

```
MODEL /path/to/other/model\n
```

Response:
```json
{"status": "ok", "model": "/path/to/other/model"}
```

Or on error:
```json
{"error": "failed to load model: /path/to/other/model"}
```

## Integration with Talkie

The `coprocess.tcl` manager handles all IPC:

```tcl
source coprocess.tcl

# Start engine
set response [::coprocess::start "whisper" \
    "python3 engines/faster_whisper_engine.py" \
    "/models/whisper-base.en" \
    16000]

# Process audio
set json_response [::coprocess::process "whisper" $audio_data]

# Get final result
set json_response [::coprocess::final "whisper"]

# Stop engine
::coprocess::stop "whisper"
```

## Benefits

- **Language agnostic** - Implement engines in any language
- **No library conflicts** - Vosk, Sherpa, Whisper can all run simultaneously
- **Crash isolation** - Engine crash doesn't kill Talkie
- **Simple protocol** - Easy to debug and test
- **JSON responses** - Compatible with existing Talkie parsing code
