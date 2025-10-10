#!/bin/bash
# Wrapper script to run faster_whisper_engine.py with venv

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Activate virtual environment
source "$PROJECT_DIR/venv/bin/activate"

# Run the engine with all arguments passed through
exec python3 "$SCRIPT_DIR/faster_whisper_engine.py" "$@"
