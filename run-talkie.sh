#!/bin/bash
# run-talkie.sh - Launch Talkie with all required library paths
#
# GEC requires: NPU driver, OpenVINO, CTranslate2, SentencePiece
# See src/gec/LIBRARIES.md for details

export LD_LIBRARY_PATH="\
$HOME/pkg/linux-npu-driver/build/lib:\
$HOME/pkg/openvino-src/bin/intel64/Release:\
$HOME/.local/lib:\
$HOME/.local/lib64"

cd "$(dirname "$0")"
exec tclsh8.6 src/talkie.tcl "$@"
