# Sherpa-ONNX Tcl Binding

Critcl-based Tcl binding for Sherpa-ONNX speech recognition, following the same pattern as `vosk/vosk.tcl` for API consistency.

## Architecture

Follows the proven Vosk pattern:
- **Model objects** - Load and manage Sherpa-ONNX recognizer instances
- **Stream objects** - Individual recognition streams (similar to Vosk recognizers)
- **Same API** - Compatible interface for easy engine switching

## API

### Loading a Model

```tcl
package require sherpa

set model [sherpa::load_model -path "path/to/model" ?options?]
```

**Options:**
- `-path <path>` - Model directory (required)
- `-provider <cpu|gpu>` - Compute provider (default: cpu)
- `-threads <n>` - Number of threads (default: 1)
- `-debug <0|1>` - Debug mode (default: 0)

### Model Commands

```tcl
# Get model information
$model info

# Create recognition stream
set stream [$model create_recognizer ?options?]

# Close model
$model close
```

**create_recognizer options:**
- `-rate <sample_rate>` - Sample rate in Hz (default: 16000)
- `-max_active_paths <n>` - Beam search paths (default: 4)
- `-confidence <threshold>` - Confidence threshold (default: 0.0)

### Stream Commands

```tcl
# Process audio data (16-bit PCM)
set result [$stream process $audio_data]

# Get final result
set final [$stream final-result]

# Reset stream state
$stream reset

# Configure stream parameters
$stream configure -max_active_paths 8 -confidence 0.5

# Get stream information
$stream info

# Close stream
$stream close
```

## Audio Format

- **Input**: 16-bit signed PCM (little-endian)
- **Sample rate**: Configurable (typically 16000 Hz)
- **Channels**: Mono
- **Conversion**: Automatically converts to float samples internally

## Results Format

Results are returned as JSON strings:

```json
{
  "text": "recognized text",
  "tokens": [...],
  "timestamps": [...]
}
```

## Model Requirements

Expects a Sherpa-ONNX streaming transducer model with:
- `encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx`
- `decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx`
- `joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx`
- `tokens.txt`

Example: `sherpa-onnx-streaming-zipformer-en-2023-06-26`

## Example Usage

```tcl
package require sherpa

# Load model
set model [sherpa::load_model -path "models/sherpa-onnx-streaming-zipformer-en-2023-06-26"]

# Create stream
set stream [$model create_recognizer -rate 16000]

# Process audio chunks
while {[gets $audio_source chunk] >= 0} {
    set result [$stream process $chunk]
    puts "Partial: [dict get $result text]"
}

# Get final result
set final [$stream final-result]
puts "Final: [dict get $final text]"

# Cleanup
$stream close
$model close
```

## Differences from Vosk

While the API is intentionally similar, there are some differences:

1. **Configuration**: Sherpa-ONNX requires model file paths at load time
2. **Options**: Different tuning parameters (max_active_paths vs beam)
3. **Results**: JSON format differs slightly from Vosk
4. **Audio conversion**: Sherpa-ONNX uses float samples internally

## Integration with Talkie

Can be used as a drop-in replacement for Vosk in the Talkie audio processing pipeline by adapting the result parsing in `audio.tcl`.

## Dependencies

- Tcl 8.6+
- Critcl 3.1+
- Sherpa-ONNX C API libraries (installed to `~/.local/`)
- ONNX Runtime

## Building

The Critcl package self-compiles on first use:

```tcl
package require sherpa
```

Or pre-compile:

```bash
cd tcl/sherpa-onnx
critcl -pkg sherpa-onnx.tcl
```

## Testing

```bash
cd tcl/sherpa-onnx
tclsh test_sherpa.tcl [model_path]
```

## Files

- `sherpa-onnx.tcl` - Main Critcl package (393 lines)
- `test_sherpa.tcl` - Test script
- `README.md` - This file

## Comparison with Vosk Implementation

| Feature | Vosk | Sherpa-ONNX |
|---------|------|-------------|
| Lines of code | 397 | 393 |
| API pattern | Object commands | Object commands |
| Subcommands | 9 | 9 |
| Options | beam, alternatives | max_active_paths |
| Audio format | 16-bit PCM | 16-bit PCM → float |
| Result format | JSON | JSON |

## License

Same as Talkie project.
