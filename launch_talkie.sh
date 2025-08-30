#!/bin/bash

echo "Talkie - Speech to Text with OpenVINO Whisper"
echo "============================================="

# Check if NPU is available
echo "Checking NPU requirements..."
python3 verify_npu.py > /dev/null 2>&1
npu_status=$?

if [ $npu_status -eq 0 ]; then
    echo "✓ NPU requirements met - will use OpenVINO Whisper with automatic device selection"
    echo "Launching Talkie with automatic engine detection..."
    python3 talkie.py --engine auto "$@"
else
    echo "⚠ NPU requirements not fully met - will use automatic fallback detection"
    echo "Launching Talkie with automatic engine detection..."
    python3 talkie.py --engine auto "$@"
fi