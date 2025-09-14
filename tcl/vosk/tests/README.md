# Vosk Tcl Binding Tests

This directory contains test scripts for the Vosk speech recognition Tcl binding.

## Test Files

### Core Functionality Tests
- **`test_vosk_basic.tcl`** - Basic Vosk model loading and recognition tests
- **`test_simple_sync.tcl`** - Simple synchronous API demonstration
- **`test_wav_file.tcl`** - Process real WAV files with automatic sample rate detection

### Performance Tests
- **`test_performance.tcl`** - Comprehensive performance analysis with different chunk sizes
- **`test_no_callbacks_multiple.tcl`** - Multiple processing calls stress test

### Integration Tests
- **`test_no_callbacks.tcl`** - PortAudio + Vosk integration test
- **`test_vosk_integration.tcl`** - Full real-time speech recognition with PortAudio
- **`test_no_streaming.tcl`** - Non-streaming processing test

### Legacy Tests
- **`test_slow_callbacks.tcl`** - Updated to synchronous processing (no callbacks)

## Running Tests

```bash
# Set up environment
export PATH="$HOME/.local/bin:$PATH"
export TCLLIBPATH="$HOME/.local/lib $TCLLIBPATH"

# Run individual tests
tclsh test_simple_sync.tcl
tclsh test_wav_file.tcl
tclsh test_performance.tcl

# Integration test (requires microphone)
tclsh test_vosk_integration.tcl
```

## Requirements

- Vosk model at `../../models/vosk-model-en-us-0.22-lgraph`
- Test audio files (optional, for WAV file tests)
- Microphone (for integration tests)

## Performance Results

The Vosk binding achieves excellent performance:
- **3-4x faster than real-time** processing
- **100ms chunks** provide optimal latency/efficiency balance
- Consistent performance across different sample rates (8kHz, 16kHz, 44.1kHz)