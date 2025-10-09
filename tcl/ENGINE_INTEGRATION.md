# Speech Engine Integration Complete

## Summary

Successfully integrated Sherpa-ONNX alongside Vosk with runtime engine selection, restart prompts, and dynamic UI configuration.

## Files Created

1. **`engine.tcl`** - Abstraction layer providing unified interface
2. **`sherpa.tcl`** - Sherpa-ONNX initialization (mirrors vosk.tcl)

## Files Modified

### 1. `talkie.tcl`
- **Dynamic engine loading** based on `config(speech_engine)`
- Early config load to determine which engine to load
- Conditional `package require` for vosk or sherpa
- Updated `get_model_path()` to support both engines

### 2. `config.tcl`
- **`config_engine_change()`** - Prompts for restart when engine changes
- **`config_model_change()`** - Uses `::engine::cleanup/initialize`
- **`config_refresh_models()`** - Loads both vosk and sherpa model lists
- Added traces for `speech_engine`, `vosk_modelfile`, `sherpa_modelfile`

### 3. `ui-layout.tcl`
- Added `speech_engine` to default config (defaults to "vosk")
- Added `sherpa_max_active_paths` and `sherpa_modelfile` to defaults
- **Dynamic `config()` proc** - Builds UI based on selected engine
  - Shows "Speech Engine" dropdown at top
  - Conditionally shows Vosk or Sherpa-specific options
  - Maintains common options (confidence, lookback, etc.)

### 4. `audio.tcl`
- Replaced all `$::vosk_recognizer` calls with `[::engine::recognizer]`
- Changed initialization to call `::engine::initialize`
- Now engine-agnostic - works with any engine

## How It Works

### Engine Selection Flow

```
1. User opens Config dialog
2. Changes "Speech Engine" dropdown (vosk → sherpa)
3. config_engine_change() triggered
4. Restart prompt shown
5. If OK: saves config, restarts app
6. If Cancel: reverts to original engine
```

### Startup Flow

```
1. talkie.tcl sources config.tcl, ui-layout.tcl
2. config_load() reads ~/.talkie.conf
3. Determines speech_engine (vosk or sherpa)
4. Dynamically loads appropriate package:
   - vosk: loads vosk package + vosk.tcl
   - sherpa: loads sherpa package + sherpa.tcl
5. Loads engine.tcl (abstraction layer)
6. Loads audio.tcl (uses abstraction)
7. audio::initialize() → engine::initialize() → vosk/sherpa::initialize()
```

### Runtime Abstraction

```tcl
# Instead of:
$::vosk_recognizer process $audio

# Now uses:
[::engine::recognizer] process $audio
```

The `::engine::recognizer` proc returns the appropriate recognizer command based on which engine was loaded.

## Configuration

### Default Config (ui-layout.tcl:38-57)

```tcl
speech_engine             vosk
vosk_beam                 20
vosk_lattice              8
vosk_alternatives         1
vosk_modelfile            vosk-model-en-us-0.22-lgraph
sherpa_max_active_paths   4
sherpa_modelfile          sherpa-onnx-streaming-zipformer-en-2023-06-26
```

### Config File (~/.talkie.conf)

```json
{
  "speech_engine": "vosk",
  "vosk_modelfile": "vosk-model-en-us-0.22-lgraph",
  "sherpa_modelfile": "sherpa-onnx-streaming-zipformer-en-2023-06-26",
  ...
}
```

## UI Behavior

### Config Dialog - Vosk Selected

```
┌─ Talkie Configuration ────┐
│ Speech Engine:  [vosk ▼]  │
│ ──────────────────────────│
│ Input Device:   [pulse ▼] │
│ Confidence:     [175    ] │
│ Lookback:       [1.0    ] │
│ Silence:        [0.5    ] │
│ ──────────────────────────│
│ Vosk Beam:      [20     ] │
│ Lattice Beam:   [8      ] │
│ Alternatives:   [1      ] │
│ Model:          [...]     │
│ ──────────────────────────│
│ ... threshold options ... │
└───────────────────────────┘
```

### Config Dialog - Sherpa Selected

```
┌─ Talkie Configuration ─────┐
│ Speech Engine:  [sherpa ▼] │
│ ───────────────────────────│
│ Input Device:   [pulse  ▼] │
│ Confidence:     [175     ] │
│ Lookback:       [1.0     ] │
│ Silence:        [0.5     ] │
│ ───────────────────────────│
│ Max Active Paths: [4     ] │
│ Model:          [...]      │
│ ───────────────────────────│
│ ... threshold options ...  │
└────────────────────────────┘
```

Notice:
- Vosk-specific options (Beam, Lattice, Alternatives) hidden
- Sherpa-specific options (Max Active Paths) shown
- Common options always visible

## Engine Isolation

### Only One Engine Loaded at Runtime

```tcl
# talkie.tcl:81-92
if {$::config(speech_engine) eq "vosk"} {
    package require vosk
    source vosk.tcl
} elseif {$::config(speech_engine) eq "sherpa"} {
    package require sherpa
    source sherpa.tcl
}
```

- Vosk and Sherpa are **never loaded together**
- No namespace conflicts
- No library conflicts
- Clean memory footprint

### Why Restart Is Required

1. **C libraries** - Can't unload shared objects safely
2. **Package state** - Tcl packages can't be truly unloaded
3. **Simplicity** - Restart is cleaner than complex cleanup
4. **User control** - Explicit restart gives user control

## Testing

### Test Vosk (Default)

```bash
cd tcl
./talkie.tcl
# Should start with Vosk engine
```

### Test Sherpa

```bash
cd tcl
./talkie.tcl
# Click Config
# Change "Speech Engine" to "sherpa"
# Click OK on restart prompt
# App should restart with Sherpa-ONNX
```

### Test Engine Switch

```bash
# With app running:
1. Config → Speech Engine → sherpa → OK
2. App restarts
3. Verify new config shows "Max Active Paths" instead of "Vosk Beam"
4. Config → Speech Engine → vosk → OK
5. App restarts
6. Verify config shows Vosk options again
```

## Model Paths

```
models/
├── vosk/
│   ├── vosk-model-en-us-0.22-lgraph/
│   └── [other vosk models]/
└── sherpa-onnx/
    ├── sherpa-onnx-streaming-zipformer-en-2023-06-26/
    └── [other sherpa models]/
```

Both engines' model lists are loaded at startup and appear in their respective dropdowns.

## Error Handling

### Unknown Engine

```tcl
# talkie.tcl:89-91
} else {
    puts "ERROR: Unknown speech engine: $::config(speech_engine)"
    exit 1
}
```

### Failed Initialization

```tcl
# engine.tcl:27-32
} else {
    puts "Unknown speech engine: $current_engine"
    return false
}
```

### Missing Config

```tcl
# talkie.tcl:77-79
if {![info exists ::config(speech_engine)]} {
    set ::config(speech_engine) "vosk"
}
```

## Benefits

1. ✅ **User choice** - Switch engines via GUI
2. ✅ **Clean isolation** - Only one engine loaded at a time
3. ✅ **Dynamic UI** - Options adapt to selected engine
4. ✅ **Restart prompt** - Clear user feedback
5. ✅ **Backwards compatible** - Existing configs default to vosk
6. ✅ **Extensible** - Easy to add more engines (whisper, etc.)

## Future Enhancements

- Add "Whisper.cpp" engine
- Per-engine confidence thresholds
- Engine-specific advanced settings panels
- Model download/management UI
- Engine benchmarking tools

## Summary of Changes

| File | Lines Changed | Purpose |
|------|---------------|---------|
| engine.tcl | +58 (new) | Abstraction layer |
| sherpa.tcl | +31 (new) | Sherpa initialization |
| talkie.tcl | ~30 modified | Dynamic loading |
| config.tcl | ~40 modified | Engine switching, model refresh |
| ui-layout.tcl | ~60 modified | Dynamic UI, defaults |
| audio.tcl | ~10 modified | Use abstraction |

**Total:** ~200 lines of well-structured changes enabling full engine flexibility.

## Conclusion

The integration successfully provides:
- Clean separation between engines
- User-friendly engine selection
- Dynamic configuration UI
- Restart-based engine switching
- Future extensibility

Both engines are now first-class citizens in Talkie!
