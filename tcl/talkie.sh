#!/bin/bash
# Shell wrapper for talkie that handles engine-change restarts
# Exit code 4 = restart requested (engine change)

cd "$(dirname "$0")"

while true; do
    ./talkie.tcl "$@"
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 4 ]; then
        echo "Restarting talkie (engine change)..."
        sleep 0.5
        continue
    else
        exit $EXIT_CODE
    fi
done
