#!/bin/bash

cd "$(dirname "$(realpath "$0")")"

# OpenVINO and NPU driver libraries for GEC inference
export LD_LIBRARY_PATH="$HOME/pkg/openvino-src/bin/intel64/Release:$HOME/pkg/linux-npu-driver/build/lib:$HOME/.local/lib:$LD_LIBRARY_PATH"
export OPENBLAS_NUM_THREADS=4

# Pin to P-cores (0-11) on Intel hybrid CPUs, fall back gracefully
TASKSET=""
if command -v taskset >/dev/null 2>&1; then
    # Check if we have hybrid architecture (P-cores + E-cores)
    if lscpu 2>/dev/null | grep -q "900.0000.*MINMHZ\|700.0000.*MINMHZ" 2>/dev/null || \
       [ "$(lscpu -e=MAXMHZ 2>/dev/null | sort -u | wc -l)" -gt 2 ]; then
        TASKSET="taskset -c 0-11"
    fi
fi

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

If no command is given, launches the Talkie GUI.
EOF
            exit 0
            ;;
        *)
            # Unknown command, pass to talkie.tcl
            ;;
    esac
fi

# Launch GUI and set WM_COMMAND for session management
$TASKSET ./talkie.tcl "$@" &
PID=$!
trap 'kill $PID 2>/dev/null' INT TERM
for i in $(seq 30); do
    WID=$(wmctrl -l -p | awk -v pid=$PID '$3 == pid {print $1; exit}')
    [ -n "$WID" ] && break
    sleep 0.1
done
[ -n "$WID" ] && xprop -id "$WID" -f WM_COMMAND 8s -set WM_COMMAND "talkie"
wait $PID
