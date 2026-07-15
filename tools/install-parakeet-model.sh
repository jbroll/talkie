#!/usr/bin/env bash
# Download the sherpa-onnx NeMo Parakeet TDT 0.6b-v2 (int8) offline model
# into models/parakeet/. ~631MB. Parakeet emits proper case + punctuation.
set -euo pipefail
DEST="$(cd "$(dirname "$0")/.." && pwd)/models/sherpa-onnx"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2"
mkdir -p "$DEST"
cd "$DEST"
echo "Downloading Parakeet model to $DEST ..."
curl -sSL "$URL" -o pk.tar.bz2
tar -xjf pk.tar.bz2
rm -f pk.tar.bz2
echo "Installed: $DEST/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
