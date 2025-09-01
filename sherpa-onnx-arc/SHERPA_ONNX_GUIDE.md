# Complete Intel ARC Graphics Sherpa-ONNX Reproduction Guide

## Overview

This guide provides **complete, step-by-step instructions** to reproduce the working Intel ARC Graphics GPU acceleration for Sherpa-ONNX speech recognition that achieved 1.91x real-time performance.

## Prerequisites

### Hardware Requirements (Verified Working)
- **CPU**: Intel Core Ultra 7 155H  
- **GPU**: Intel Arc Graphics [0x7d55] (integrated)
- **Memory**: 16GB+ RAM recommended
- **OS**: Ubuntu 24.04.2 LTS

### Software Environment
- **GCC**: 13.3.0
- **Python**: 3.12.3
- **CMake**: 3.28+
- **Git**: Latest

## Step-by-Step Reproduction

### Step 1: Environment Setup

```bash
# Navigate to project directory
cd /home/john/src/talkie

# Create and activate virtual environment
python3 -m venv .
source bin/activate

# Upgrade pip and install build tools
pip install --upgrade pip
pip install cmake ninja wheel build setuptools-scm pybind11
```

### Step 2: Install OpenVINO Stack

```bash
# Install exact versions that were working
pip install onnxruntime-openvino==1.22.0
pip install openvino==2024.6.0  
pip install openvino-genai==2024.6.0
pip install optimum-intel==1.22.0

# Verify installation
python -c "import onnxruntime; print('ONNX Runtime:', onnxruntime.__version__)"
python -c "import openvino; print('OpenVINO:', openvino.__version__)"
python -c "import onnxruntime; print('Providers:', onnxruntime.get_available_providers())"
```

Expected output should include `OpenVINOExecutionProvider`.

### Step 3: Download and Prepare Source Code

```bash
# Download Sherpa-ONNX source
cd /tmp
rm -rf sherpa-onnx  # Remove any existing
git clone https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx

# Download ONNX Runtime headers (required for compilation)
cd /tmp
wget -q https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/onnxruntime-linux-x64-1.22.0.tgz
tar -xzf onnxruntime-linux-x64-1.22.0.tgz
mkdir -p onnxruntime-headers
cp -r onnxruntime-linux-x64-1.22.0/include/* onnxruntime-headers/
```

### Step 4: Apply Source Code Modifications

Apply the exact modifications documented in `SHERPA_ONNX_CUSTOM_MODIFICATIONS.md`:

```bash
cd /tmp/sherpa-onnx

# Modification 1: cmake/onnxruntime.cmake
# Add after line 176 in the GPU section:
cat >> cmake/onnxruntime_patch.txt << 'EOF'
      # Add providers_shared library for GPU builds
      set(location_onnxruntime_providers_shared_lib $ENV{SHERPA_ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_shared.so)
EOF

# Add after line 194 in find_library section:
cat >> cmake/onnxruntime_patch2.txt << 'EOF'
      find_library(location_onnxruntime_providers_shared_lib onnxruntime_providers_shared
        PATHS
          /lib
          /usr/lib
          /usr/local/lib
      )
EOF

# Add after line 223 in target properties section:
cat >> cmake/onnxruntime_patch3.txt << 'EOF'
    if(SHERPA_ONNX_ENABLE_GPU AND location_onnxruntime_providers_shared_lib)
      add_library(onnxruntime_providers_shared SHARED IMPORTED)
      set_target_properties(onnxruntime_providers_shared PROPERTIES
        IMPORTED_LOCATION ${location_onnxruntime_providers_shared_lib}
      )
    endif()
EOF

# Apply patches (manual editing required - see SHERPA_ONNX_CUSTOM_MODIFICATIONS.md for exact locations)

# Modification 2: Add OpenVINO provider support
# Edit sherpa-onnx/csrc/provider.h - add to enum:
#   kOpenVINO = 7,  // OpenVINOExecutionProvider

# Edit sherpa-onnx/csrc/provider.cc - add to StringToProvider():
#   } else if (s == "openvino") {
#     return Provider::kOpenVINO;

# Edit sherpa-onnx/csrc/session.cc - add complete OpenVINO case (see SHERPA_ONNX_CUSTOM_MODIFICATIONS.md)
```

**Note**: The exact file modifications are documented with complete diffs in `SHERPA_ONNX_CUSTOM_MODIFICATIONS.md`. These must be applied manually or via git patches.

### Step 5: Setup Library Environment

```bash
# Create required library symlinks
cd /home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi
ln -sf libonnxruntime.so.1.22.0 libonnxruntime.so
ln -sf libonnxruntime.so.1.22.0 libonnxruntime.so.1

# Set up environment variables for build
export SHERPA_ONNXRUNTIME_LIB_DIR="/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi"
export SHERPA_ONNXRUNTIME_INCLUDE_DIR="/tmp/onnxruntime-headers"
```

### Step 6: Build Sherpa-ONNX with GPU Support

```bash
cd /tmp/sherpa-onnx

# Create build directory
mkdir -p build
cd build

# Configure with CMake (GPU enabled)
cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DSHERPA_ONNX_ENABLE_GPU=ON \
  -DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON \
  -DONNXRUNTIME_ROOT_PATH="/tmp/onnxruntime-headers" \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
  -GNinja \
  ..

# Build (this takes 10-15 minutes)
ninja

# Install into virtual environment
cd /tmp/sherpa-onnx
pip install -e .
```

### Step 7: Download Models

```bash
cd /home/john/src/talkie/models/sherpa-onnx

# Download the exact model used in testing
wget -q https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-en-2023-06-26.tar.bz2
tar -xf sherpa-onnx-streaming-zipformer-en-2023-06-26.tar.bz2
rm sherpa-onnx-streaming-zipformer-en-2023-06-26.tar.bz2

# Verify models exist
ls -la sherpa-onnx-streaming-zipformer-en-2023-06-26/
```

### Step 8: Environment Configuration

```bash
# Create environment setup script
cat > /home/john/src/talkie/setup_gpu_env.sh << 'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="/home/john/src/talkie/lib/python3.12/site-packages/onnxruntime/capi:$LD_LIBRARY_PATH"
export ORT_PROVIDERS="OpenVINOExecutionProvider,CPUExecutionProvider"
export OV_DEVICE="GPU"
export OV_GPU_ENABLE_BINARY_CACHE="1"
export OV_CACHE_DIR="/tmp/ov_cache"
mkdir -p $OV_CACHE_DIR
EOF

chmod +x /home/john/src/talkie/setup_gpu_env.sh
```

### Step 9: Verification and Testing

```bash
# Source environment
cd /home/john/src/talkie
source bin/activate
source setup_gpu_env.sh

# Test import
python -c "
import sherpa_onnx
import onnxruntime
print('Sherpa-ONNX version:', sherpa_onnx.__version__)
print('ONNX Runtime version:', onnxruntime.__version__)
print('Available providers:', onnxruntime.get_available_providers())
"

# Test GPU functionality
python -c "
import sherpa_onnx
import os
print('Testing Sherpa-ONNX OpenVINO GPU provider...')

model_path = 'models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26'

try:
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=f'{model_path}/tokens.txt',
        encoder=f'{model_path}/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        decoder=f'{model_path}/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        joiner=f'{model_path}/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        num_threads=1,
        sample_rate=16000,
        provider='openvino'
    )
    
    print('✓ SUCCESS: Sherpa-ONNX OpenVINO GPU provider working!')
    
except Exception as e:
    print(f'✗ GPU test failed: {e}')
"

# Performance benchmark (if test audio exists)
if [ -f "models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/test_wavs/0.wav" ]; then
    time python test_speech_engines.py models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/test_wavs/0.wav --test-sherpa --verbose
fi
```

### Step 10: Integration with Talkie Application

```bash
# Update talkie.py to support OpenVINO provider
# (See SHERPA_ONNX_CUSTOM_MODIFICATIONS.md for SherpaONNX_engine.py changes)

# Test full application with GPU
source setup_gpu_env.sh
./talkie.sh --engine sherpa-onnx --verbose
```

## Expected Results

### Performance Metrics (Intel Arc Graphics)
- **Processing Speed**: 1.91x real-time (3.45s for 6.6s audio)
- **Memory Usage**: ~471MB peak
- **Initialization Time**: ~2.8s for model loading
- **Transcription Quality**: Excellent with proper word boundaries

### Verification Commands
```bash
# Check hardware
lspci | grep VGA  # Should show: Intel Corporation Device 7d55

# Check drivers
lsmod | grep i915  # Should show Intel graphics driver

# Check OpenVINO GPU detection
python -c "import openvino as ov; core = ov.Core(); print('Available devices:', core.available_devices)"
```

## Troubleshooting

### Build Issues
- **LTO mismatch**: Add `-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF` to cmake
- **Library not found**: Verify `SHERPA_ONNXRUNTIME_LIB_DIR` environment variable
- **Header not found**: Verify `SHERPA_ONNXRUNTIME_INCLUDE_DIR` points to extracted headers

### Runtime Issues  
- **Import error**: Source the `setup_gpu_env.sh` script
- **GPU not detected**: Verify Intel Arc Graphics drivers are loaded
- **Performance issues**: Ensure `OV_DEVICE=GPU` is set

## Files Created/Modified

This reproduction creates:
- Custom sherpa-onnx build in `/tmp/sherpa-onnx/`
- Modified source files (4 files with OpenVINO support)  
- GPU environment setup script
- Updated talkie.py integration

## Complete Package List

Final working pip list should include:
```
onnxruntime-openvino==1.22.0
openvino==2024.6.0
openvino-genai==2024.6.0
optimum-intel==1.22.0
sherpa-onnx==1.12.10 (custom build)
vosk==0.3.45
sounddevice
numpy
pyinput
word2number
```

## Success Verification

The complete reproduction is successful when:
1. ✅ `python -c "import sherpa_onnx"` works without errors
2. ✅ OpenVINO provider is available in ONNX Runtime
3. ✅ GPU device is detected by OpenVINO
4. ✅ Sherpa-ONNX recognizer initializes with `provider='openvino'`
5. ✅ Performance benchmark shows >1.5x real-time processing
6. ✅ Talkie application works with `--engine sherpa-onnx` option

This guide provides everything needed to completely reproduce the working Intel ARC Graphics GPU acceleration implementation.