# GEC - Grammar Error Correction for Talkie

Neural network-based grammar correction for speech recognition output using Intel NPU acceleration via OpenVINO.

## Features

- **Homophone correction**: Fixes common homophones (their/there/they're, your/you're, etc.) using ELECTRA masked language modeling
- **Punctuation restoration**: Adds periods, commas, question marks using DistilBERT token classification
- **Capitalization**: Proper sentence and proper noun capitalization
- **NPU acceleration**: Runs on Intel NPU for fast inference (~5ms per model call)

## Requirements

### Hardware
- Intel CPU with integrated NPU (e.g., Core Ultra 7 155H)

### Software
- Tcl 8.6
- OpenVINO (built from source with NPU support)
- Intel NPU driver (linux-npu-driver)

### Models
Located in `models/gec/`:
- `electra-small-generator.onnx` - ELECTRA model for homophone correction
- `distilbert-punct-cap.onnx` - DistilBERT model for punctuation/capitalization

### Data
- `data/homophones.json` - Homophone groups generated from pronunciation dictionary
- `src/gec/vocab.txt` - BERT vocabulary for tokenization

## Environment Setup

The GEC system requires OpenVINO and NPU driver libraries. Set `LD_LIBRARY_PATH` before running:

```bash
export LD_LIBRARY_PATH="$HOME/pkg/openvino-src/bin/intel64/Release:$HOME/pkg/linux-npu-driver/build/lib:$LD_LIBRARY_PATH"
```

This is automatically configured in `src/talkie.sh`.

## Usage

### From Talkie

GEC is automatically initialized when Talkie starts:

```bash
./src/talkie.sh
```

The startup log shows:
```
gec_pipeline: Loading punctcap model...
gec_pipeline: Loading homophone model...
homophone: loaded 2780 single-token, 12309 multi-token homophones
gec_pipeline: Initialized (2780 homophone groups)
GEC: Initialized on NPU
```

### Standalone Testing

```tcl
#!/usr/bin/env tclsh8.6
lappend auto_path src/gec/lib src/wordpiece/lib
source src/gec.tcl

# Initialize
::gec::init

# Process text
set result [::gec::process "i wonder weather it will rain"]
# Output: "I wonder whether it will rain"

# Get timing info
puts [::gec::last_timing]
# Output: homo_ms 25.3 punct_ms 8.2 total_ms 33.5
```

### Running Tests

```bash
LD_LIBRARY_PATH=... tclsh8.6 src/gec/test_gec.tcl
```

Expected output:
```
=== GEC OpenVINO Bindings Tests ===
...
  NPU device available... OK
  inference on NPU... OK
  NPU is faster than CPU... (CPU: 8453us, NPU: 5307us) OK
...
All tests passed!
```

## Architecture

```
src/gec/
├── gec.tcl          # Critcl OpenVINO bindings (C code)
├── pipeline.tcl     # GEC pipeline orchestration
├── punctcap.tcl     # Punctuation/capitalization module
├── homophone.tcl    # Homophone correction module
├── vocab.txt        # BERT vocabulary
├── test_gec.tcl     # Test suite
└── lib/             # Compiled critcl package
    └── gec/
```

### Processing Pipeline

1. **Input**: Raw lowercase text from Vosk speech recognition
2. **Homophone correction**: ELECTRA MLM scores alternatives, picks highest probability
3. **Punctuation/capitalization**: DistilBERT predicts class per token (24 classes)
4. **Output**: Properly formatted text

### Key Optimizations

- **get_best_token**: Extracts only needed logits instead of copying 1.9M floats (~50μs vs ~114ms)
- **NPU inference**: ~5ms per model call vs ~9ms on CPU
- **Lowercase bias**: Prevents over-capitalization of mid-sentence words

## Performance

Typical timing per phrase on Intel NPU:
- Homophone correction: 20-50ms (depends on number of homophones)
- Punctuation/capitalization: 8-15ms
- Total: 30-65ms per phrase

## Troubleshooting

### NPU not detected

Check `gec::devices` returns both CPU and NPU:
```tcl
package require gec
puts [gec::devices]  ;# Should show: CPU NPU
```

If only CPU shows:
1. Verify `/dev/accel0` exists
2. Check user is in `video` group
3. Ensure both library paths are in `LD_LIBRARY_PATH`:
   - OpenVINO: `$HOME/pkg/openvino-src/bin/intel64/Release`
   - NPU driver: `$HOME/pkg/linux-npu-driver/build/lib`

### Model compilation fails

If NPU compilation fails with `GENERAL_ERROR`, the NPU may not support runtime compilation. Pre-compiled blobs would be needed (not currently implemented).

### Slow homophone correction

If homophone correction takes >100ms, check that `get_best_token` is being used (not `get_output`). Rebuild the gec package:
```bash
/usr/bin/critcl -pkg -libdir src/gec/lib src/gec/gec.tcl
```

## Building the Critcl Package

After modifying `src/gec/gec.tcl`:

```bash
rm -rf src/gec/lib/gec
/usr/bin/critcl -pkg -libdir src/gec/lib src/gec/gec.tcl
```

Use `/usr/bin/critcl` (not `~/bin/critcl`) to ensure Tcl 8.6 target.
