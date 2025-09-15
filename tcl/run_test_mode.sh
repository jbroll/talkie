#!/bin/bash
# Run talkie in test mode and filter for pipeline messages

echo "=== Running Talkie in Test Mode ==="
echo "Starting talkie with instrumented pipeline output..."
echo "The GUI will appear - click 'Start Transcription' to see the audio pipeline in action"
echo ""

env TCLLIBPATH="$HOME/.local/lib" tclsh talkie_python_like.tcl -test 2>&1 | \
grep -E "(TEST MODE|TRANSCRIPTION-|DEVICE-|VOSK-|PA-CALLBACK|ENERGY-|UI-|VOICE-ACTIVITY)" | \
head -100