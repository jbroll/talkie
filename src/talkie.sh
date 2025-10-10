#!/bin/bash

cd "$(dirname "$(realpath "$0")")"

# Command-line interface
if [ $# -gt 0 ]; then
    case "$1" in
        state)
            # Show current transcription state
            cat "$HOME/.talkie" 2>/dev/null || echo '{"transcribing": false}'
            exit 0
            ;;
        toggle)
            # Toggle transcription on/off
            STATE=$(cat "$HOME/.talkie" 2>/dev/null | grep -o '"transcribing":[^,}]*' | grep -o '[^:]*$' | tr -d ' ')
            case "$STATE" in
                true|1) "$0" stop ;;
                *) "$0" start ;;
            esac
            exit 0
            ;;
        start)
            # Start transcription
            echo '{"transcribing": true}' > "$HOME/.talkie"
            command -v slim >/dev/null 2>&1 && slim mute on
            exit 0
            ;;
        stop)
            # Stop transcription
            echo '{"transcribing": false}' > "$HOME/.talkie"
            command -v slim >/dev/null 2>&1 && slim mute off
            exit 0
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [COMMAND]

Commands:
  state      Show current transcription state
  toggle     Toggle transcription on/off
  start      Start transcription (and mute audio if slim available)
  stop       Stop transcription (and unmute audio if slim available)
  --help     Show this help message

If no command is given, launches the Talkie GUI with auto-restart on engine change.

Exit code 4 indicates restart requested (engine change).
EOF
            exit 0
            ;;
        *)
            # Unknown command, pass to talkie.tcl
            ;;
    esac
fi

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
