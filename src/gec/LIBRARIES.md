# GEC Library Dependencies

**IMPORTANT**: The GEC pipeline requires specific library paths to enable NPU acceleration.

## Required LD_LIBRARY_PATH

```bash
export LD_LIBRARY_PATH=\
$HOME/pkg/linux-npu-driver/build/lib:\
$HOME/pkg/openvino-src/bin/intel64/Release:\
$HOME/.local/lib:\
$HOME/.local/lib64
```

## Library Sources

| Library | Path | Purpose |
|---------|------|---------|
| `libze_intel_npu.so` | `~/pkg/linux-npu-driver/build/lib/` | Intel NPU Level-Zero backend |
| `libze_loader.so` | `~/pkg/linux-npu-driver/build/lib/` | Level-Zero loader |
| `libopenvino.so` | `~/pkg/openvino-src/bin/intel64/Release/` | OpenVINO runtime |
| `libopenvino_c.so` | `~/pkg/openvino-src/bin/intel64/Release/` | OpenVINO C API |
| `libopenvino_intel_npu_plugin.so` | `~/pkg/openvino-src/bin/intel64/Release/` | OpenVINO NPU plugin |
| `libctranslate2.so` | `~/.local/lib64/` | CTranslate2 (T5 grammar) |
| `libsentencepiece.so` | `~/.local/lib/` | SentencePiece tokenizer |

## Quick Test

```bash
# Set library path
export LD_LIBRARY_PATH=$HOME/pkg/linux-npu-driver/build/lib:$HOME/pkg/openvino-src/bin/intel64/Release:$HOME/.local/lib:$HOME/.local/lib64

# Verify NPU is available
tclsh8.6 -c 'lappend auto_path src/gec/lib; package require gec; puts [gec::devices]'
# Should output: CPU NPU
```

## Running Talkie with GEC

```bash
cd ~/src/talkie
export LD_LIBRARY_PATH=$HOME/pkg/linux-npu-driver/build/lib:$HOME/pkg/openvino-src/bin/intel64/Release:$HOME/.local/lib:$HOME/.local/lib64
tclsh8.6 src/talkie.tcl
```

## Shell Alias (add to ~/.bashrc or ~/.zshrc)

```bash
alias talkie='LD_LIBRARY_PATH=$HOME/pkg/linux-npu-driver/build/lib:$HOME/pkg/openvino-src/bin/intel64/Release:$HOME/.local/lib:$HOME/.local/lib64 tclsh8.6 ~/src/talkie/src/talkie.tcl'
```

## Pipeline Stages and Devices

| Stage | Model | Device | Library |
|-------|-------|--------|---------|
| 1. Homophone | ELECTRA | NPU | OpenVINO |
| 2. Punct/Caps | DistilBERT | NPU | OpenVINO |
| 3. Grammar | T5 | CPU | CTranslate2 |

## Troubleshooting

**NPU not detected:**
```bash
# Check if NPU hardware exists
lspci | grep -i npu
# Should show: Intel Corporation Meteor Lake NPU

# Check if level-zero libraries are found
ldd ~/pkg/openvino-src/bin/intel64/Release/libopenvino_intel_npu_plugin.so | grep "not found"
# Should have no output (all libraries found)
```

**Model loading fails:**
```bash
# Verify library paths
echo $LD_LIBRARY_PATH | tr ':' '\n'
```
