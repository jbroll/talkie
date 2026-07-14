#!/usr/bin/env bash
# Install prebuilt sherpa-onnx C shared library + headers into ~/.local
set -euo pipefail
URL="${1:?usage: install-sherpa-onnx-lib.sh <linux-x64-shared.tar.bz2 URL>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading $URL"
curl -sSL "$URL" -o "$TMP/sherpa.tar.bz2"
tar -xjf "$TMP/sherpa.tar.bz2" -C "$TMP"
SRC="$(find "$TMP" -maxdepth 1 -type d -name 'sherpa-onnx-*')"
mkdir -p "$HOME/.local/lib" "$HOME/.local/include"
cp -av "$SRC"/lib/. "$HOME/.local/lib/"
cp -av "$SRC"/include/. "$HOME/.local/include/"
echo "Installed sherpa-onnx libs to ~/.local/lib and headers to ~/.local/include"
