# Vosk Speech Recognition - Tcl Binding

This directory contains a **stable, high-performance Tcl binding** for the Vosk speech recognition library, providing real-time speech-to-text capabilities with a native Tcl interface.

## Features

- **Synchronous API** - Simple, reliable speech recognition without callback complexity
- **High Performance** - 3-4x faster than real-time processing
- **Multiple Sample Rates** - Supports 8kHz, 16kHz, 44.1kHz, and other rates
- **WAV File Processing** - Direct processing of audio files with automatic format detection
- **Real-time Integration** - Works seamlessly with PortAudio for live speech recognition
- **Memory Safe** - No memory leaks or segmentation faults
- **Production Ready** - Thoroughly tested and optimized

## Files

- **vosk.tcl** - Main Tcl binding implementation using CRITCL
- **tests/** - Comprehensive test suite and examples
- **lib/** - Compiled Vosk library package

## Building the Binding

```bash
# Ensure vosk_api.h is available
sudo find /usr -name "vosk_api.h" 2>/dev/null

# Build the binding
critcl -pkg vosk vosk.tcl
```

## Tcl API Reference

### Initialization

```tcl
package require vosk
Vosk_Init
```

### Core Functions

#### vosk::set_log_level
Set Vosk logging verbosity level.

```tcl
vosk::set_log_level level
```

- **level**: Integer log level (-1 = quiet, 0 = errors, 1 = warnings, 2 = info, 3 = debug)

#### vosk::load_model
Load a speech recognition model from disk.

```tcl
set model [vosk::load_model -path model_path]
```

- **-path**: Path to Vosk model directory
- **Returns**: Model command object

### Model Commands

#### $model info
Get information about the loaded model.

```tcl
set info [$model info]
```

- **Returns**: Dictionary with model information

#### $model create_recognizer
Create a speech recognizer instance.

```tcl
set recognizer [$model create_recognizer ?options?]
```

**Options:**
- **-rate sample_rate**: Audio sample rate (default: 16000)
- **-beam value**: Beam search width (default: 20)
- **-confidence threshold**: Confidence threshold (default: 0.0)
- **-alternatives count**: Maximum alternatives to return (default: 1)

- **Returns**: Recognizer command object

#### $model close
Close the model and free resources.

```tcl
$model close
```

### Recognizer Commands

#### $recognizer process
Process audio data chunk and return results synchronously.

```tcl
set result [$recognizer process audio_data]
```

- **audio_data**: Raw 16-bit PCM audio data
- **Returns**: JSON string with recognition results (partial or final)

#### $recognizer final_result
Get final recognition result.

```tcl
set result [$recognizer final_result]
```

- **Returns**: JSON string with final recognition result

#### $recognizer reset
Reset recognizer state to start new recognition session.

```tcl
$recognizer reset
```

#### $recognizer configure
Configure recognizer parameters.

```tcl
$recognizer configure ?options?
```

**Options:**
- **-alternatives count**: Maximum alternatives to return
- **-confidence threshold**: Confidence threshold for results
- **-beam value**: Beam search width

#### $recognizer info
Get recognizer configuration information.

```tcl
set info [$recognizer info]
```

- **Returns**: Dictionary with recognizer configuration

#### $recognizer close
Close recognizer and free resources.

```tcl
$recognizer close
```

## JSON Result Format

Recognition results are returned as JSON strings with the following structure:

### Partial Results
```json
{
  "partial": "hello wor"
}
```

### Final Results
```json
{
  "text": "hello world",
  "confidence": 0.95,
  "words": [
    {
      "word": "hello",
      "start": 0.0,
      "end": 0.5,
      "conf": 0.98
    },
    {
      "word": "world",
      "start": 0.6,
      "end": 1.0,
      "conf": 0.92
    }
  ]
}
```

### Multiple Alternatives
```json
{
  "alternatives": [
    {
      "text": "hello world",
      "confidence": 0.95
    },
    {
      "text": "hello word",
      "confidence": 0.85
    }
  ]
}
```

## Usage Examples

### Basic Recognition

```tcl
package require vosk
Vosk_Init

# Load model
set model [vosk::load_model -path "../models/vosk-model-en-us-0.22-lgraph"]

# Create recognizer
set recognizer [$model create_recognizer -rate 16000]

# Process audio data (16-bit PCM, 16kHz)
set result [$recognizer process $audio_data]
puts "Recognition: $result"

# Get final result
set final [$recognizer final_result]
puts "Final: $final"

# Cleanup
$recognizer close
$model close
```

### Processing WAV Files

```tcl
package require vosk
Vosk_Init

# Load model
set model [vosk::load_model -path "../models/vosk-model-en-us-0.22-lgraph"]

# Read WAV file (simplified - see test_wav_file.tcl for complete implementation)
set fp [open "speech.wav" rb]
seek $fp 44  ;# Skip WAV header
set audio_data [read $fp]
close $fp

# Create recognizer matching the audio file's sample rate
set recognizer [$model create_recognizer -rate 44100]

# Process in chunks for better results
set chunk_size 3200
set data_len [string length $audio_data]
for {set i 0} {$i < $data_len} {incr i $chunk_size} {
    set chunk [string range $audio_data $i [expr {$i + $chunk_size - 1}]]
    set result [$recognizer process $chunk]

    # Parse partial results
    if {[regexp {"text"\s*:\s*"([^"]*)"} $result -> text]} {
        if {$text ne ""} {
            puts "Partial: $text"
        }
    }
}

# Get final result
set final [$recognizer final_result]
puts "Final: $final"

# Cleanup
$recognizer close
$model close
```

### Real-time Recognition with PortAudio

```tcl
package require pa
package require vosk

# Initialize both systems
Pa_Init
Vosk_Init

# Load speech model
set model [vosk::load_model -path "../models/vosk-model-en-us-0.22-lgraph"]
set recognizer [$model create_recognizer -rate 16000]

# Audio callback processes data synchronously
proc audio_callback {stream timestamp data} {
    global recognizer

    # Process audio chunk
    set result [$recognizer process $data]

    # Parse and display results
    if {[regexp {"text"\s*:\s*"([^"]*)"} $result -> text]} {
        if {$text ne ""} {
            puts "Speech: $text"
        }
    }
}

# Create audio stream (16-bit PCM, 16kHz to match Vosk)
set stream [pa::open_stream \
    -device default \
    -rate 16000 \
    -channels 1 \
    -format int16 \
    -callback audio_callback]

$stream start

# Let it run for 30 seconds
after 30000 {
    $stream stop

    # Get final result
    set final [$recognizer final_result]
    puts "Final result: $final"

    # Cleanup
    $stream close
    $recognizer close
    $model close
    exit
}

vwait forever
```

### Advanced Configuration

```tcl
package require vosk
Vosk_Init

# Set quiet logging
vosk::set_log_level -1

# Load model
set model [vosk::load_model -path "../models/vosk-model-en-us-0.22-lgraph"]

# Create recognizer with advanced settings
set recognizer [$model create_recognizer \
    -rate 16000 \
    -alternatives 3 \
    -confidence 0.7 \
    -beam 15]

# Get recognizer info
puts "Recognizer info: [$recognizer info]"

# Reconfigure during runtime
$recognizer configure -confidence 0.5 -alternatives 1

# Process audio with high-quality settings
set result [$recognizer process $audio_data]
puts "Result: $result"
```

## Performance

The Vosk binding achieves excellent performance:

- **Real-time Factor**: 0.25x - 0.31x (3-4x faster than real-time)
- **Latency**: 100ms chunks provide optimal balance
- **Memory Usage**: Efficient with automatic cleanup
- **Sample Rates**: All rates supported (8kHz, 16kHz, 44.1kHz, etc.)

### Performance Tuning

#### Beam Search Parameters

- **beam**: Controls accuracy vs. speed tradeoff
  - Higher values (20-30): More accurate, slower
  - Lower values (10-15): Faster, less accurate
  - Default: 20

#### Confidence Filtering

- **confidence**: Filters low-confidence results
  - 0.0-0.3: Accept most results (noisy)
  - 0.4-0.7: Balanced filtering
  - 0.8-1.0: Only high-confidence results

#### Memory Usage

- Use appropriate model sizes:
  - Small models (~50MB): Fast, less accurate
  - Large models (~1GB): Slower, more accurate
- Close recognizers when not needed
- Reuse recognizer instances when possible

## Audio Format Requirements

- **Sample Rate**: Any rate supported by Vosk (8kHz, 16kHz, 44.1kHz, etc.)
- **Format**: 16-bit signed PCM
- **Channels**: 1 (mono)
- **Endianness**: Little-endian (native)

## Troubleshooting

### Common Issues

1. **"Package not found"**
   - Ensure TCLLIBPATH includes the lib directory
   - Verify the binding was built successfully

2. **"Model load failed"**
   - Check model path exists and is valid Vosk model
   - Verify read permissions on model directory

3. **"No recognition results"**
   - Check audio format matches requirements (16-bit PCM)
   - Verify audio data is not silent or corrupted
   - Lower confidence threshold for testing
   - Ensure sample rate matches recognizer configuration

4. **"Poor recognition quality"**
   - Verify sample rate matching between audio and recognizer
   - Check audio quality and noise levels
   - Adjust beam search and confidence parameters

### Debug Tips

```tcl
# Enable verbose logging
vosk::set_log_level 3

# Check model info
set model [vosk::load_model -path $model_path]
puts [$model info]

# Check recognizer configuration
set recognizer [$model create_recognizer -rate 16000]
puts [$recognizer info]

# Test with known audio data
set silence [string repeat "\x00" 3200]  ;# 0.1s of silence
puts [$recognizer process $silence]
```

## Testing

Run the provided test scripts to verify functionality:

```bash
# Set environment
export PATH="$HOME/.local/bin:$PATH"
export TCLLIBPATH="$HOME/.local/lib $TCLLIBPATH"

# Basic functionality test
tclsh tests/test_simple_sync.tcl

# WAV file processing test
tclsh tests/test_wav_file.tcl

# Performance analysis
tclsh tests/test_performance.tcl

# Integration test with PortAudio (requires microphone)
tclsh tests/test_vosk_integration.tcl
```

## License

This Vosk Tcl binding is distributed under the Apache 2.0 License, consistent with the Vosk speech recognition library.