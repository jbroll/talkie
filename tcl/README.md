# Tcl Speech Recognition Bindings

This directory contains Tcl bindings for audio processing and speech recognition:

- **pa/** - PortAudio binding for real-time audio capture
- **vosk/** - Vosk speech recognition binding and examples

## Dependencies

### System Dependencies

1. **PortAudio** (for audio capture):
   ```bash
   sudo apt-get install portaudio19-dev libportaudio2
   ```

2. **Vosk** (for speech recognition):
   ```bash
   # Install Vosk development files
   sudo apt-get install libvosk-dev libvosk0

   # Alternative: Build from source
   git clone https://github.com/alphacep/vosk-api
   cd vosk-api/src
   make
   sudo make install
   ```

3. **CRITCL** (for Tcl C bindings):
   ```bash
   # Install from source (recommended)
   git clone https://github.com/andreas-kupries/critcl.git
   cd critcl
   tclsh build.tcl install --prefix ~/.local
   export PATH="$HOME/.local/bin:$PATH"
   export TCLLIBPATH="$HOME/.local/lib $TCLLIBPATH"
   ```

### Speech Models

Download a Vosk speech recognition model:

```bash
# English model (large)
wget https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-lgraph.zip
unzip vosk-model-en-us-0.22-lgraph.zip -d ~/Downloads/

# English model (small, faster)
wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
unzip vosk-model-small-en-us-0.15.zip -d ~/Downloads/
```

## Building the Bindings

1. **Build PortAudio binding**:
   ```bash
   cd pa/
   critcl -pkg pa pa.tcl
   ```

2. **Build Vosk binding**:
   ```bash
   # First ensure vosk_api.h is available
   sudo find /usr -name "vosk_api.h" 2>/dev/null

   # Build the binding
   cd vosk/
   critcl -pkg vosk vosk.tcl
   ```

## Usage Examples

### Basic Audio Capture (PortAudio)
```tcl
package require pa
Pa_Init

# List available devices
foreach device [pa::list_devices] {
    puts [dict get $device name]
}

# Create audio stream with callback
proc audio_callback {stream timestamp data} {
    puts "Received [string length $data] bytes at $timestamp"
}

set stream [pa::open_stream -device default -rate 44100 -channels 1 -callback audio_callback]
$stream start

# Let it run for 5 seconds
after 5000 {
    $stream stop
    $stream close
}
vwait forever
```

### Speech Recognition (Vosk)
```tcl
package require vosk
Vosk_Init

# Load model
set model [vosk::load_model -path ~/Downloads/vosk-model-en-us-0.22-lgraph]

# Create recognizer with callback
proc speech_callback {recognizer json is_final} {
    puts "Speech result: $json (final: $is_final)"
}

set recognizer [$model create_recognizer -rate 16000 -callback speech_callback]

# Process audio data (from PortAudio or file)
$recognizer process $audio_data

# Cleanup
$recognizer close
$model close
```

### Combined Real-time Transcription
```tcl
# See vosk/speech_transcription_example.tcl for complete working example
package require pa
package require vosk

# Initialize both systems
Pa_Init
Vosk_Init

# Load speech model
set model [vosk::load_model -path ~/Downloads/vosk-model-en-us-0.22-lgraph]
set recognizer [$model create_recognizer -rate 16000 -callback speech_callback]

# Audio callback feeds data to speech recognizer
proc audio_callback {stream timestamp data} {
    global recognizer
    $recognizer process $data
}

# Create audio stream
set stream [pa::open_stream -device default -rate 16000 -channels 1 \
                           -format int16 -callback audio_callback]
$stream start
```

## Testing

Run the test scripts to verify functionality:

```bash
# Test basic functionality
cd vosk/
./test_vosk_basic.tcl

# Test integration with PortAudio
./test_vosk_integration.tcl

# Complete example
./speech_transcription_example.tcl
```

## API Reference

### PortAudio Binding (pa::)

- `pa::init` - Initialize PortAudio
- `pa::list_devices` - List available audio devices
- `pa::open_stream ?options?` - Create audio stream
  - Options: `-device`, `-rate`, `-channels`, `-frames`, `-format`, `-callback`

### Stream Commands
- `$stream start` - Start audio capture
- `$stream stop` - Stop audio capture
- `$stream info` - Get stream information
- `$stream stats` - Get performance statistics
- `$stream close` - Close stream

### Vosk Binding (vosk::)

- `vosk::init` - Initialize Vosk
- `vosk::load_model -path <path>` - Load speech recognition model
- `vosk::set_log_level <level>` - Set logging level (-1 = quiet)

### Model Commands
- `$model info` - Get model information
- `$model create_recognizer ?options?` - Create recognizer
  - Options: `-rate`, `-callback`, `-beam`, `-confidence`, `-alternatives`
- `$model close` - Close model

### Recognizer Commands
- `$recognizer process <audio_data>` - Process audio chunk
- `$recognizer reset` - Reset recognition state
- `$recognizer final_result` - Get final result
- `$recognizer configure ?options?` - Configure parameters
- `$recognizer set_callback <script>` - Set result callback
- `$recognizer info` - Get recognizer information
- `$recognizer close` - Close recognizer

## Audio Format Compatibility

The bindings are designed to work together seamlessly:

- PortAudio captures audio in **16-bit PCM** format
- Vosk expects **16-bit PCM** at **16kHz** sample rate
- Audio data flows directly from PortAudio callbacks to Vosk processing
- No format conversion needed when using compatible settings

## Performance Considerations

- Use appropriate buffer sizes (1024-4096 frames recommended)
- Set Vosk confidence threshold to filter noise (0.3-0.7 typical)
- Monitor overflows/underruns in audio statistics
- Consider beam parameters for accuracy vs. speed tradeoff

## Troubleshooting

### Common Issues

1. **"Package not found"** - Ensure TCLLIBPATH includes built packages
2. **"Headers not found"** - Install development packages for PortAudio/Vosk
3. **"No audio devices"** - Check microphone permissions and PulseAudio
4. **"Model load failed"** - Verify model path and file integrity
5. **"Compilation errors"** - Check GCC and development tools installed

### Debug Mode

```tcl
# Enable Critcl debug mode
critcl -keep -show -debug symbols -pkg pa pa.tcl

# Enable audio debugging
set stream [pa::open_stream -device default -rate 16000 -channels 1]
puts [$stream info]
```

## License

These bindings follow the same license as the underlying libraries:
- PortAudio: MIT-style license
- Vosk: Apache 2.0 license
- CRITCL: BSD-style license