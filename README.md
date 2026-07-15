<h1 style="display: flex; align-items: center;"><img src="icon.svg" alt="Talkie Icon" width="64" height="64" style="margin-right: 15px;"/> Talkie - Voice-to-keyboard for Linux</h1>

Real-time speech-to-text transcription with keyboard simulation for Linux.

## Description
<img src="screenshot.png" alt="Talkie Desktop UI" align="right" width="40%"/>

Talkie is a speech recognition application that transcribes audio input and simulates keyboard events to inject text into the active window. It runs continuously in the background with a Tk-based control interface.

The application monitors microphone input, performs voice activity detection, transcribes speech using configurable recognition engines, applies light text processing (spacing, voice-command macros, sentence capitalization), and types the results via the Linux uinput subsystem.
<br clear="right"/>

## Features

- Real-time audio transcription
- Multiple speech recognition engines:
  - **Vosk** (Kaldi, streaming, in-process)
  - **sherpa-onnx** (in-process) — one engine that auto-detects the model kind and runs streaming Zipformer, offline Parakeet (TDT & CTC), Moonshine, Whisper, SenseVoice, and NVIDIA Canary

  Both engines run in-process (critcl); there is no external/Python engine.
- Voice activity detection: energy threshold or **Silero VAD** (OpenVINO, CPU/NPU)
- Capability-aware endpointing: streaming models finalize on their own end-of-utterance signal; batch models finalize on VAD-silence or partial-stability
- Utterance-level confidence filtering
- Keyboard event simulation via uinput
- Voice command macro system (punctuation, symbols, formatting)
- External control via file-based IPC
- Persistent JSON configuration with XDG support
- Single-instance enforcement (TCP socket on port 47823)
- Feedback logging for STT analysis
- Automatic audio stream health monitoring and recovery

> **Note:** An earlier GEC/homophone pipeline (grammar/punctuation/homophone correction via OpenVINO) was removed — the experiments were not reliable. Modern engines (Parakeet, Moonshine, Whisper, Canary) emit their own punctuation and casing.

## Architecture

```
src/
├── talkie.tcl          # Main application entry point
├── talkie.sh           # Startup script (library paths, CLI)
├── config.tcl          # Configuration management
├── engine.tcl          # Audio capture + speech processing workers, engine registry
├── stt.tcl             # Common stt:: engine dispatch (in-process critcl engines)
├── finalization.tcl    # engine::should_finalize (self-endpoint vs partial-stability)
├── audio.tcl           # Result display, transcription state, device enumeration
├── worker.tcl          # Reusable worker thread abstraction
├── output.tcl          # Post-processing (filters, textproc) + uinput typing
├── textproc.tcl        # Macro-based text preprocessing and voice commands
├── ui-layout.tcl       # Tk interface
├── feedback.tcl        # Feedback logging
├── vad_silero.tcl      # Silero VAD (OpenVINO, CPU/NPU) with resampling
├── vosk.tcl            # Vosk engine helpers
├── pa/                 # PortAudio critcl bindings
├── audio/              # Audio energy calculation critcl bindings
├── vosk/               # Vosk critcl bindings
├── sherpa/             # sherpa-onnx critcl bindings (online + offline recognizers)
├── ov/                 # OpenVINO inference bindings (for Silero VAD)
├── uinput/             # uinput critcl bindings
└── tests/              # Test suite (tcltest)
```

### Threading Architecture

Audio processing is fully decoupled from the main thread through a multi-worker architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Main Thread                               │
│  ┌──────────────────────┐  ┌─────────────────────────────────┐  │
│  │   Tk GUI (5Hz)        │  │   Result Display                │  │
│  │   - Controls          │  │   - final_text(), partial_text()│  │
│  │   - Audio / VAD level  │  │   - Timing info display         │  │
│  └──────────────────────┘  └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
        ▲                                ▲
        │ thread::send -async            │ thread::send -async
        │ (UI updates)                   │ (display notifications)
┌───────┴───────────────┐  ┌─────────────┴───────────────────────┐
│   Audio Worker         │  │        Processing Worker            │
│  ┌─────────────────┐  │  │  ┌───────────────────────────────┐  │
│  │ PortAudio        │──┼──┼─▶│ VAD (energy or Silero)         │  │
│  │ Callbacks (40Hz) │  │  │  │ STT (vosk / sherpa-onnx / ...) │  │
│  └─────────────────┘  │  │  │ finalization decision          │  │
└───────────────────────┘  │  └───────────────┬───────────────┘  │
                           └──────────────────┼───────────────────┘
                                              │ thread::send -async
                                              ▼
                              ┌─────────────────────────────────┐
                              │        Output Worker            │
                              │  killword + confidence filter,  │
                              │  textproc, then uinput typing   │
                              └─────────────────────────────────┘

Pipeline: Audio → Processing → Output   (Output also notifies Main for display)
```

**Data Flow:**
1. **Audio Worker**: PortAudio delivers ~25ms chunks, queues to Processing (never blocks). Stale chunks (>500ms old) are dropped to prevent backlog after suspend/idle.
2. **Processing Worker**: VAD (energy threshold or Silero) + speech recognition. For `self`-endpoint engines (streaming sherpa/vosk) it finalizes on the recognizer's endpoint; for `external` engines it uses `engine::should_finalize` (energy-silence OR partial-stability).
3. **Output Worker**: killword + utterance-level confidence filtering, `textproc` (spacing/voice-commands/capitalization), then uinput typing. Lowercases ALL-CAPS recognizer output so sentence-casing applies (Parakeet/Moonshine/Whisper/Canary already emit proper case).
4. **Main Thread**: GUI updates throttled to 5Hz.

### Engine abstraction

The common contract lives in `src/stt.tcl` (`stt::` namespace): `create`, `process` → `{partial endpoint}`, `final` → `{text confidence}`, `reset`, `destroy`. Engines are declared in `engine_registry` (`engine.tcl`) with per-engine `endpointing` and `emits_partials`.

The `sherpa-onnx` engine inspects the selected model directory (`sherpa::detect_kind`) and dispatches to the right recognizer:

| Detected kind | Example model | Endpointing |
|---|---|---|
| online-transducer | streaming Zipformer | self (streaming, partials) |
| offline-transducer | Parakeet TDT 0.6B | external (batch) |
| offline-ctc | Parakeet CTC 110M | external (batch) |
| moonshine | Moonshine tiny.en | external (batch) |
| whisper | whisper tiny.en | external (batch) |
| sense-voice | SenseVoice | external (batch) |
| canary | NVIDIA Canary 180M | external (batch) |

Batch (offline) recognizers buffer the utterance's audio during `process` and decode once in `final-result`.

## Dependencies

### System Requirements
- Linux kernel with uinput support
- Tcl/Tk 9 (see `MEMORY`/CLAUDE notes for the specific toolchain)
- PortAudio
- User must be a member of the `input` group for uinput access

### For sherpa-onnx engines
- sherpa-onnx C shared library + headers — install with `tools/install-sherpa-onnx-lib.sh <url>` (into `~/.local`)

### For Silero VAD (optional)
- OpenVINO (the `ov` critcl package); Intel NPU optional (falls back to CPU, then to energy threshold)

### Tcl Packages
- Tk, Thread, json
- jbr::unix, jbr::filewatch, jbr::pipe (used by textproc)
- pa, audio, uinput, vosk, sherpa, ov (critcl)

### Speech Engine Models
Place under the `models/` directory:
- **Vosk**: `models/vosk/vosk-model-en-us-0.22-lgraph`
- **sherpa-onnx**: `models/sherpa-onnx/<any supported model>` — all sherpa models (streaming, Parakeet, Moonshine, Whisper, SenseVoice, Canary) live here and appear together in the Model dropdown; the engine auto-detects the kind. See [MODELS.md](MODELS.md).

### Data Files
- `talkie.map` — voice command macro definitions

## Installation

### 1. Build critcl Bindings
```bash
cd src
make build
```
This compiles the PortAudio, audio, uinput, Vosk, sherpa, and OpenVINO critcl packages.

### 2. Install the sherpa-onnx C library (for sherpa-onnx engines)
```bash
# Find the latest linux-x64-shared release at
# https://github.com/k2-fsa/sherpa-onnx/releases and pass its URL:
tools/install-sherpa-onnx-lib.sh <sherpa-onnx-...-linux-x64-shared.tar.bz2 URL>
```

### 3. Configure uinput Access
```bash
sudo modprobe uinput
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf   # optional, persist
sudo usermod -a -G input $USER                              # then log out/in
```

### 4. Download Speech Models
See [MODELS.md](MODELS.md). Example (a fast, high-quality English offline model):
```bash
tools/install-parakeet-model.sh   # Parakeet TDT 0.6B into models/sherpa-onnx/
```

## Usage

### Starting the Application
```bash
cd src
./talkie.sh
```
The GUI window appears. Only one instance runs at a time; additional launches raise the existing window. The startup script configures library paths and pins to P-cores on Intel hybrid CPUs.

### Command-Line Interface
```bash
./talkie.sh start       # Enable transcription (and mute audio if slim available)
./talkie.sh stop        # Disable transcription (and unmute audio)
./talkie.sh toggle      # Toggle transcription state
./talkie.sh state       # Display current state as JSON
./talkie.sh --help      # Show help
```

### External Control
```bash
echo '{"transcribing": true}'  > ~/.talkie   # Start
echo '{"transcribing": false}' > ~/.talkie   # Stop
```
The application monitors this file and updates state within 500ms.

### Voice Commands
During transcription, speak these commands to insert punctuation and symbols. Defined in `talkie.map`, processed by `textproc.tcl`.

**Sentence endings** (end of utterance only): "period" → `.`, "question mark" → `?`, "exclamation mark"/"exclamation point" → `!`

**Line breaks** (end of utterance only): "new line"/"newline" → `\n`, "new paragraph" → `\n\n`

**Mid-sentence**: "comma" → `,`, "colon" → `:`, "semicolon" → `;`, "ellipsis" → `...`

**Connectors** (no surrounding space): "hyphen"/"dash" → `-`, "apostrophe" → `'`

**Quotes/brackets**: "open/close quote" → `"`, "open/close paren" → `(` `)`

**Symbols**: "at sign" `@`, "hashtag"/"pound sign" `#`, "dollar sign" `$`, "asterisk" `*`, "slash" `/`, "underscore" `_`, "ampersand" `&`, "percent" `%`, "plus sign" `+`, "equals" `=`, "less than" `<`, "greater than" `>`

## Configuration

Configuration file: `$XDG_CONFIG_HOME/talkie.conf` or `~/.talkie.conf` (JSON, auto-saved on change).

### Selected Settings
```json
{
    "speech_engine": "sherpa-onnx",
    "sherpa_modelfile": "sherpa-onnx-moonshine-tiny-en-int8",
    "sherpa_num_threads": 4,
    "vosk_modelfile": "vosk-model-en-us-0.22-lgraph",
    "input_device": "default",
    "vad_engine": "threshold",
    "vad_device": "CPU",
    "vad_threshold": 0.5,
    "vad_end_threshold": 0.35,
    "audio_threshold": 25.0,
    "silence_seconds": 0.3,
    "partial_stable_seconds": 0.6,
    "min_duration": 0.30,
    "lookback_seconds": 0.5,
    "spike_suppression_seconds": 0.3,
    "confidence_threshold": 100,
    "typing_delay_ms": 5
}
```

### Key Parameters

- **speech_engine**: `"vosk"` or `"sherpa-onnx"`.
- **sherpa_modelfile**: model directory under `models/sherpa-onnx/`; the kind (streaming/offline/CTC/whisper/...) is auto-detected.
- **sherpa_num_threads**: CPU threads for sherpa inference (default 4). Strongly affects offline decode latency on multi-core machines.
- **vad_engine**: `"threshold"` (energy) or `"silero"`. **vad_device**: `CPU`/`NPU` (Silero only). **vad_threshold** / **vad_end_threshold**: Silero Schmitt-trigger thresholds.
- **audio_threshold**: energy-VAD threshold. **silence_seconds**: silence before finalizing. **partial_stable_seconds**: finalize a segment when a non-empty partial stays unchanged this long (external-endpoint engines; `<= 0` disables).
- **confidence_threshold**: utterance-level confidence filter (Vosk provides it; models without confidence pass through).
- **lookback_seconds**, **spike_suppression_seconds**, **min_duration**, **typing_delay_ms**: as named.

All parameters can be adjusted via the GUI or by editing the config file. Changes take effect immediately via variable traces; engine and model changes hot-swap without restarting.

## Feedback Logging

Talkie logs to `~/.config/talkie/feedback.jsonl` (JSON Lines) for analysis.

| Type | Description | Fields |
|------|-------------|--------|
| `inject` | Text sent to uinput | `text` |

## Performance

### Audio Processing
- **Sample Rate**: device rate (e.g. 44.1kHz), resampled as needed
- **Chunk Size**: ~25ms; **Callback Rate**: 40Hz on the audio worker
- **VAD**: energy threshold or Silero (with Schmitt-trigger hysteresis)
- **Lookback**: configurable pre-speech buffering (default 0.5s)
- **Backlog protection**: stale chunks (>500ms) dropped to recover from suspend/idle

### STT latency (indicative, on a fast multi-core CPU, int8 models)
- **Streaming Zipformer**: real-time partials, no post-speech wait.
- **Moonshine tiny.en**: ~0.18s to decode a ~7s utterance (RTF ~0.03); excellent English quality.
- **Parakeet TDT 0.6B**: ~0.6s for a ~7s utterance at 4 threads (RTF ~0.09); highest English accuracy.
- Offline decode scales with utterance length and `sherpa_num_threads`.

## Development

### Building
```bash
cd src && make build       # all critcl packages
cd src/sherpa && make test # sherpa binding tests (needs the C lib + models)
cd src/tests && tclsh all_tests.tcl
```

### Adding a Speech Engine
1. Add an entry to `engine_registry` in `src/engine.tcl`.
2. Add a critcl package under `src/` and a `stt::create` branch in `src/stt.tcl`.

### Adding a sherpa-onnx model type
Wire its config struct + a `create_offline_*_recognizer` command in `src/sherpa/sherpa.tcl`, add a `detect_kind` name marker + a `load_*_model` wrapper + a `load_auto` case in `src/sherpa/sherpa_procs.tcl`.

### Adding Voice Commands
Edit `talkie.map`:
```
"spoken phrase"   "output"   [attachment]
```
Attachment: `<` (attach left), `>` (attach right), `<>` (both), omit for normal spacing. Append `$` to match end-of-utterance only.

## Troubleshooting

### uinput Permission Denied / Not Found
Verify `input` group membership (`groups | grep input`) after logout/in, and load the module (`sudo modprobe uinput`). On Void Linux: `make fix-uinput` (temporary) or `make install-uinput-service` (permanent).

### Audio Device Errors
List devices and update the config: `pactl list sources short` (PulseAudio).

### Speech Engine Model Not Found
Verify the model directory in the config matches an actual directory under `models/`. A failed engine no longer crashes startup — the GUI comes up with a warning so you can pick a working engine in Settings.

### sherpa-onnx model runs on CPU only
The prebuilt sherpa-onnx library exposes CPU/CUDA/CoreML, not an Intel-NPU path for ASR. The VAD "Device" (CPU/NPU) option applies to **Silero VAD only**, not the STT model.

## License

MIT

## Author

john@rkroll.com
