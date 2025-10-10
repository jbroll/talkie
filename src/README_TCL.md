# Talkie Tcl Edition

A Tcl implementation of the Talkie speech-to-text application using existing PortAudio and Vosk bindings.

## Architecture

This Tcl implementation uses a dual-interpreter architecture:

1. **Main UI Interpreter**: Handles the Tkinter GUI, configuration, and user interaction
2. **Audio Worker Interpreter**: Manages audio capture via PortAudio and speech recognition via Vosk

The two interpreters communicate via aliases, allowing the audio worker to call back to the main UI for displaying partial and final recognition results.

## Features Based on Python Implementation

- **Real-time Speech Recognition**: Uses existing Vosk Tcl binding
- **Audio Device Management**: PortAudio integration for device selection and audio capture
- **GUI Interface**: Tkinter-based interface with:
  - Transcription toggle button
  - Audio device selection
  - Energy and confidence displays
  - Real-time transcription display with partial results
  - Configuration controls (energy threshold, confidence threshold)
- **Configuration Persistence**: JSON-based configuration storage
- **Text Processing**: Punctuation mapping and text formatting
- **Dual-Interpreter Design**: Separation of UI and audio processing for responsiveness

## Dependencies

### Required Packages
- Tcl/Tk 8.6+
- critcl (for building C extensions)
- PortAudio library and headers
- Vosk library and headers
- json package for Tcl

### Existing Bindings Used
- `pa.tcl`: PortAudio binding from `pa/` directory
- `vosk.tcl`: Vosk speech recognition binding from `vosk/` directory

## Building

```bash
# Install dependencies
make deps

# Build packages
make all

# Test the build
make test

# Run the application
make run
```

## Manual Build

If the Makefile doesn't work:

```bash
# Build PortAudio package
cd pa
tclsh pa.tcl

# Build Vosk package
cd ../vosk
tclsh vosk.tcl

# Run main application
cd ..
tclsh talkie_main.tcl
```

## Usage

### Starting the Application

```bash
./talkie_main.tcl
```

### GUI Controls

- **Start/Stop Transcription**: Toggle button to enable/disable speech recognition
- **Audio Device**: Dropdown to select input device
- **Energy Threshold**: Slider to adjust voice activity detection sensitivity
- **Confidence Threshold**: Slider to filter low-confidence recognition results
- **Energy Display**: Real-time audio energy level
- **Confidence Display**: Current recognition confidence with color coding

### Voice Commands

The application processes the same voice commands as the Python version:
- "period" → "."
- "comma" → ","
- "question mark" → "?"
- "new line" → "\n"
- etc.

## Configuration

Configuration is stored in `~/.talkie_tcl.conf` as JSON:

```json
{
    "energy_threshold": 50.0,
    "sample_rate": 16000,
    "frames_per_buffer": 1600,
    "silence_timeout": 3.0,
    "window_x": 100,
    "window_y": 100,
    "vosk_model_path": "/home/john/Downloads/vosk-model-en-us-0.22-lgraph",
    "confidence_threshold": 280.0
}
```

## Audio Processing Flow

1. **PortAudio Capture**: Audio is captured via PortAudio stream with callback
2. **Worker Interpreter**: Audio data is processed in the secondary interpreter
3. **Vosk Recognition**: Audio chunks are sent to Vosk for recognition
4. **Callback Communication**: Results are sent back to main interpreter via aliases
5. **UI Updates**: Main interpreter updates the GUI with partial/final results
6. **Text Processing**: Final results are processed for punctuation and formatting

## Key Differences from Python Version

### Advantages
- **Native Tcl Integration**: Uses pure Tcl packages instead of Python bindings
- **Lightweight**: Lower memory footprint than Python version
- **Direct C Integration**: critcl provides efficient C code integration
- **Existing Bindings**: Leverages battle-tested PortAudio and Vosk bindings

### Current Limitations
- **Callback Implementation**: Audio callback mechanism needs refinement
- **Threading**: Tcl's event-driven model differs from Python's threading
- **Keyboard Simulation**: Not yet implemented (would need uinput binding)
- **Advanced Features**: Some Python features not yet ported

## File Structure

```
tcl/
├── talkie_main.tcl          # Main application
├── test_integration.tcl     # Integration tests
├── Makefile                 # Build system
├── pa/                      # PortAudio binding (existing)
│   ├── pa.tcl
│   └── lib/
├── vosk/                    # Vosk binding (existing)
│   ├── vosk.tcl
│   └── lib/
└── README_TCL.md           # This file
```

## Development Notes

### Inter-Interpreter Communication

The dual-interpreter design uses Tcl's `interp alias` mechanism:

```tcl
# Main interpreter creates worker
set audio_interp [interp create audio_worker]

# Set up aliases for callbacks
$audio_interp alias partial_result ::talkie::handle_partial
$audio_interp alias final_result ::talkie::handle_final
```

### Audio Callback Pattern

The audio processing follows this pattern:

```tcl
# In worker interpreter
proc audio_callback {input_data} {
    set result [$recognizer process $input_data]
    if {$is_final} {
        final_result $text $confidence
    } else {
        partial_result $text $confidence
    }
}
```

### Error Handling

Extensive error handling ensures graceful degradation:

```tcl
if {[catch {package require pa} err]} {
    puts "Error loading PortAudio: $err"
    # Fallback or exit gracefully
}
```

## Future Improvements

1. **Keyboard Simulation**: Integrate uinput for text insertion
2. **Audio Callback Refinement**: Improve real-time audio processing
3. **Configuration UI**: Add settings dialog
4. **Bubble Mode**: Implement minimized floating window
5. **Multiple Engines**: Support for different speech recognition engines
6. **Performance Optimization**: Fine-tune audio buffer management

## Testing

Run the test suite:

```bash
make test

# Or manually:
tclsh test_integration.tcl

# Performance tests:
tclsh test_integration.tcl perf

# Memory tests:
tclsh test_integration.tcl memory
```

## Troubleshooting

### Package Not Found
```bash
# Ensure packages are built
cd pa && tclsh pa.tcl
cd ../vosk && tclsh vosk.tcl
```

### Audio Issues
```bash
# Check PortAudio devices
tclsh -c "package require pa; pa::init; puts [pa::list_devices]"
```

### Vosk Model Issues
```bash
# Verify model path
ls -la /home/john/Downloads/vosk-model-en-us-0.22-lgraph
```