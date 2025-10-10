#!/bin/bash
# Test full Talkie integration with different engines

echo "=== Testing Full Talkie Integration ==="
echo ""

# Function to test engine startup
test_engine() {
    local engine=$1
    echo "--- Testing $engine engine ---"

    # Update config
    jq --arg engine "$engine" '.speech_engine = $engine' ~/.talkie.conf > /tmp/talkie.conf.tmp
    mv /tmp/talkie.conf.tmp ~/.talkie.conf

    # Launch Talkie in background with timeout
    timeout 5s env LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH ./talkie.tcl 2>&1 | grep -E "(✓|ERROR|engine|Engine)" | head -10 &

    # Wait for it to start
    sleep 3

    # Kill any remaining processes
    pkill -f "talkie.tcl" 2>/dev/null

    echo ""
}

# Test each engine
test_engine "vosk"
test_engine "faster-whisper"
test_engine "vosk"  # Switch back to verify

echo "=== Tests Complete ==="
