#!/bin/bash
# Wrapper to launch Sherpa-ONNX engine with proper Python environment

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Activate venv if it exists
if [ -f "$PROJECT_DIR/venv/bin/activate" ]; then
    source "$PROJECT_DIR/venv/bin/activate"
fi

# Run the engine
exec python3 "$SCRIPT_DIR/sherpa_engine.py" "$@"
