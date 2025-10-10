#!/bin/bash
# Manual test of the protocol

cd "$(dirname "$0")"

# Start engine
engines/faster_whisper_wrapper.sh ../models/faster-whisper 16000 <<EOF
FINAL
EOF
