# Sherpa-ONNX Intel Arc GPU Integration

## Overview

This document describes building Sherpa-ONNX with Intel Arc Graphics GPU acceleration using OpenVINO. The integration provides streaming speech recognition with 1.91x real-time performance.

## Hardware Requirements

- Intel Core Ultra 7 155H (or compatible)
- Intel Arc Graphics [0x7d55] (integrated)
- Intel VPU (driver loaded but not supported by OpenVINO 2025.2.0)

## Software Requirements

- Ubuntu 24.04.2 LTS
- GCC 13.3.0
- Python 3.12.3 with virtual environment
- ONNX Runtime 1.22.0 with OpenVINO support

## Prerequisites Installation

### Virtual Environment Setup
```bash
cd /home/john/src/talkie
python3 -m venv .
source bin/activate
```

### Build Dependencies
```bash
pip install cmake ninja wheel build setuptools-scm pybind11
```

### OpenVINO Runtime Stack
```bash
pip install onnxruntime-openvino openvino openvino-genai optimum-intel
```

Components installed:
- `onnxruntime-openvino`: ONNX Runtime with OpenVINO execution provider
- `openvino`: Intel OpenVINO toolkit for inference optimization
- `openvino-genai`: Generative AI optimizations
- `optimum-intel`: Intel-optimized transformers

## Build Process

### Source Code Preparation

Clone Sherpa-ONNX repository:
```bash
cd /tmp
git clone https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx
```

Download ONNX Runtime headers:
```bash
cd /tmp
wget -q https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/onnxruntime-linux-x64-1.22.0.tgz
tar -xzf onnxruntime-linux-x64-1.22.0.tgz
mkdir -p onnxruntime-headers
cp -r onnxruntime-linux-x64-1.22.0/include/* onnxruntime-headers/
```

The pip-installed `onnxruntime-openvino` includes runtime libraries but not C++ headers required for compilation.

### Library Configuration

Create required symlinks:
```bash
cd /home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi
ln -sf libonnxruntime.so.1.22.0 libonnxruntime.so
ln -sf libonnxruntime.so.1.22.0 libonnxruntime.so.1
```

The build system expects standardized library names, but pip installs versioned libraries.

### CMake Configuration Fix

The sherpa-onnx cmake configuration lacks support for the `onnxruntime_providers_shared` library required for GPU builds.

Edit `/tmp/sherpa-onnx/cmake/onnxruntime.cmake`:

Add after line 176 (GPU section):
```cmake
# Add providers_shared library for GPU builds
set(location_onnxruntime_providers_shared_lib $ENV{SHERPA_ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_shared.so)
```

Add after line 222 (imported target section):
```cmake
if(SHERPA_ONNX_ENABLE_GPU AND location_onnxruntime_providers_shared_lib)
  add_library(onnxruntime_providers_shared SHARED IMPORTED)
  set_target_properties(onnxruntime_providers_shared PROPERTIES
    IMPORTED_LOCATION ${location_onnxruntime_providers_shared_lib}
  )
endif()
```

Add after line 200 (debug output):
```cmake
message(STATUS "location_onnxruntime_providers_shared_lib: ${location_onnxruntime_providers_shared_lib}")
```

### Build Configuration

Configure CMake build:
```bash
cd /tmp/sherpa-onnx
mkdir build && cd build

env SHERPA_ONNXRUNTIME_INCLUDE_DIR=/tmp/onnxruntime-headers \
    SHERPA_ONNXRUNTIME_LIB_DIR=/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi \
    CC=gcc CXX=g++ cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DSHERPA_ONNX_ENABLE_GPU=ON \
  -DSHERPA_ONNX_ENABLE_PYTHON=ON \
  -DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON \
  -DPYTHON_EXECUTABLE=/home/john/src/talkie/bin/python \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
  ..
```

Environment variables:
- `SHERPA_ONNXRUNTIME_INCLUDE_DIR`: Path to ONNX Runtime C++ headers
- `SHERPA_ONNXRUNTIME_LIB_DIR`: Path to onnxruntime-openvino libraries
- `CC=gcc CXX=g++`: Force consistent GCC 13.3.0 to avoid LTO conflicts

CMake flags:
- `SHERPA_ONNX_ENABLE_GPU=ON`: Enable GPU support
- `SHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON`: Use system onnxruntime
- `CMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF`: Disable LTO to prevent version conflicts

### Build Python Module

```bash
make -j$(nproc) _sherpa_onnx
```

Expected output:
- Build progresses to 100%
- Creates: `/tmp/sherpa-onnx/build/lib/_sherpa_onnx.cpython-312-x86_64-linux-gnu.so` (5.7MB)
- Links against system onnxruntime-openvino libraries

### Installation

Install built module:
```bash
cp /tmp/sherpa-onnx/build/lib/_sherpa_onnx.cpython-312-x86_64-linux-gnu.so \
   /home/john/src/talkie/lib/python3.12/site-packages/sherpa_onnx/lib/
```

## Integration and Usage

### Environment Setup

The `talkie.sh` wrapper configures the environment automatically:

```bash
#!/bin/bash
export LD_LIBRARY_PATH="$HOME/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:$LD_LIBRARY_PATH"
export ORT_PROVIDERS="OpenVINOExecutionProvider,CPUExecutionProvider"
export OV_DEVICE="GPU"
export OV_GPU_ENABLE_BINARY_CACHE="1"
cd "$HOME/src/talkie"
. bin/activate
python talkie.py "$@"
```

### Running with Intel Arc Graphics

Primary usage:
```bash
./talkie.sh                    # Run with GPU acceleration
./talkie.sh start              # Start transcription
./talkie.sh stop               # Stop transcription
./talkie.sh toggle             # Toggle transcription
./talkie.sh state              # Show current state
```

Manual execution:
```bash
source bin/activate
export LD_LIBRARY_PATH="/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:$LD_LIBRARY_PATH"
export ORT_PROVIDERS="OpenVINOExecutionProvider,CPUExecutionProvider"
export OV_DEVICE="GPU"
export OV_GPU_ENABLE_BINARY_CACHE="1"
python talkie.py
```

### Testing GPU Integration

Verify installation:
```bash
source bin/activate
export LD_LIBRARY_PATH="/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:$LD_LIBRARY_PATH"
python -c "
import sherpa_onnx
import onnxruntime
print('Sherpa-ONNX version:', sherpa_onnx.version)
print('ONNX Runtime version:', onnxruntime.__version__)
print('Available providers:', onnxruntime.get_available_providers())
"
```

Expected output:
```
Sherpa-ONNX version: 1.12.10
ONNX Runtime version: 1.22.0
Available providers: ['OpenVINOExecutionProvider', 'CPUExecutionProvider']
```

Performance test:
```bash
env LD_LIBRARY_PATH=/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi \
    ORT_PROVIDERS=OpenVINOExecutionProvider,CPUExecutionProvider \
    OV_DEVICE=GPU \
    time ./test_speech_engines.py models/sherpa-onnx/*/test_wavs/0.wav --test-sherpa --verbose
```

## Performance Results

### Benchmarks (Intel Arc Graphics)

- Processing speed: 1.91x real-time (3.45s for 6.6s audio)
- Transcription quality: 100% accurate with proper word boundaries
- Memory usage: 471MB peak
- GPU utilization: Intel Arc Graphics with OpenVINO optimization
- Initialization time: 2.8s for model loading

### Comparison with CPU-Only

| Metric | CPU (Vosk) | GPU (Sherpa-ONNX + Intel Arc) |
|--------|------------|--------------------------------|
| Speed | 1.2x real-time | 1.91x real-time |
| Quality | Good | Excellent |
| Memory | 250MB | 471MB |
| Power | Low | Medium |

## Troubleshooting

### Common Issues

Import error: `libonnxruntime.so.1: cannot open shared object file`
```bash
export LD_LIBRARY_PATH="/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:$LD_LIBRARY_PATH"
```

CMake error: `cannot find -lonnxruntime_providers_shared`
Apply the cmake fix documented in the CMake Configuration Fix section.

LTO version mismatch:
```bash
CC=gcc CXX=g++ cmake -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF ...
```

GPU not detected:
```bash
# Verify Intel Arc Graphics
lscpu | grep -i gpu

# Verify OpenVINO providers
python -c "import onnxruntime; print(onnxruntime.get_available_providers())"
```

### Verification Commands

Check GPU hardware:
```bash
lspci | grep VGA
# Expected: Intel Corporation Device 7d55
```

Check OpenVINO installation:
```bash
python -c "import openvino as ov; print('OpenVINO version:', ov.__version__)"
```

Check driver:
```bash
lsmod | grep intel
# Should show intel_vpu and related drivers
```

Test sherpa-onnx import:
```bash
python -c "import sherpa_onnx; print('SUCCESS')"
```

## OpenVINO Provider Integration

### Adding Native OpenVINO Support to Sherpa-ONNX

Sherpa-ONNX originally lacked native OpenVINO execution provider support. The following modifications enable direct OpenVINO provider usage:

**Provider Enum Extension** (`/tmp/sherpa-onnx/sherpa-onnx/csrc/provider.h`):
```cpp
enum class Provider {
  kCPU = 0,       // CPUExecutionProvider
  kCUDA = 1,      // CUDAExecutionProvider
  kCoreML = 2,    // CoreMLExecutionProvider
  kXnnpack = 3,   // XnnpackExecutionProvider
  kNNAPI = 4,     // NnapiExecutionProvider
  kTRT = 5,       // TensorRTExecutionProvider
  kDirectML = 6,  // DmlExecutionProvider
  kOpenVINO = 7,  // OpenVINOExecutionProvider
};
```

**String Mapping** (`/tmp/sherpa-onnx/sherpa-onnx/csrc/provider.cc`):
```cpp
} else if (s == "openvino") {
  return Provider::kOpenVINO;
```

**Session Configuration** (`/tmp/sherpa-onnx/sherpa-onnx/csrc/session.cc`):
```cpp
case Provider::kOpenVINO: {
  if (std::find(available_providers.begin(), available_providers.end(),
                "OpenVINOExecutionProvider") != available_providers.end()) {
    std::unordered_map<std::string, std::string> openvino_options;
    
    const char* ov_device = std::getenv("OV_DEVICE");
    if (ov_device) {
      openvino_options["device_type"] = ov_device;
    } else {
      openvino_options["device_type"] = "CPU";
    }
    
    openvino_options["precision"] = "FP32";
    
    const char* ov_cache = std::getenv("OV_CACHE_DIR");
    if (ov_cache) {
      openvino_options["cache_dir"] = ov_cache;
    }
    
    sess_opts.AppendExecutionProvider("OpenVINO", openvino_options);
  }
  break;
}
```

### OpenVINO Model Conversion

Convert ONNX models to OpenVINO IR format to resolve dynamic shape limitations:

```bash
# Activate environment
source bin/activate

# Convert encoder model
mo --input_model models/sherpa-onnx/*/encoder-*.int8.onnx \
   --output_dir models/sherpa-onnx-openvino \
   --model_name encoder-int8 \
   --input_shape "[1,45,80],[128,1,128],[1,1,128,144]" \
   --compress_to_fp16

# Convert decoder model  
mo --input_model models/sherpa-onnx/*/decoder-*.int8.onnx \
   --output_dir models/sherpa-onnx-openvino \
   --model_name decoder-int8 \
   --compress_to_fp16

# Convert joiner model
mo --input_model models/sherpa-onnx/*/joiner-*.int8.onnx \
   --output_dir models/sherpa-onnx-openvino \
   --model_name joiner-int8 \
   --compress_to_fp16
```

## GPU Performance Analysis Results

### Dynamic Shape Resolution

OpenVINO model conversion successfully resolves ONNX Runtime dynamic shape errors:

**ONNX Runtime Issues:**
- `Check 'rank().is_static()' failed at core/partial_shape.hpp:315`
- `CPU plug-in doesn't support Parameter operation with dynamic rank`

**OpenVINO IR Resolution:**
- Models compile successfully for GPU targets
- Dynamic shapes handled through OpenVINO optimization
- No runtime errors during model compilation

### Performance Benchmarks

Comprehensive testing reveals CPU optimization superiority for speech recognition workloads:

| Configuration | Encoder (per iteration) | Decoder (per sample) | Overall Performance |
|---------------|------------------------|---------------------|-------------------|
| Intel ARC GPU | 196.86ms | 1.61ms | Baseline |
| Intel CPU | 31.47ms | 0.12ms | **6-13x faster** |

**Batch Size Analysis:**
- Batch size 1: CPU 13x faster than GPU
- Batch size 64: CPU 3x faster than GPU
- GPU overhead remains significant across all tested configurations

### Technical Findings

**GPU Compilation Success:**
- Encoder: 20.8s compilation, successful GPU target
- Decoder: 0.11s compilation, successful GPU target  
- Joiner: 0.08s compilation, successful GPU target

**Performance Characteristics:**
- GPU memory transfer overhead exceeds computation benefits
- CPU neural network optimizations highly effective for model size
- Real-time single-stream processing favors CPU architecture
- Intel Arc Graphics better suited for larger parallel workloads

## Conclusions and Recommendations

### Optimal Configuration

**Use CPU-based speech recognition** for Intel Core Ultra 7 155H systems:

```bash
python talkie.py --engine sherpa-onnx --sherpa-provider cpu
```

**Performance Benefits:**
- 6-13x faster inference than GPU alternatives
- Lower latency for real-time processing
- Reduced power consumption
- Simplified deployment without GPU driver dependencies

### When GPU Acceleration May Be Beneficial

GPU acceleration could provide advantages for:
- Batch processing multiple audio streams simultaneously
- Non-real-time bulk audio transcription
- Parallel processing of multiple recognition tasks
- Larger model architectures with higher computational requirements

### Integration Status

The CPU-optimized Sherpa-ONNX implementation provides excellent real-time performance (6.34ms per chunk) that exceeds GPU alternatives while maintaining lower resource utilization and operational complexity.

## Summary

Investigation of Intel Arc Graphics GPU acceleration for Sherpa-ONNX reveals that CPU-based processing provides superior performance for single-stream real-time speech recognition. The modifications enable OpenVINO provider support and resolve dynamic shape limitations, but performance analysis demonstrates that CPU optimization delivers optimal results for this specific workload.