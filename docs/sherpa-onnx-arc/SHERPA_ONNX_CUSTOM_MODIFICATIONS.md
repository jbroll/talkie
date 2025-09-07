# Sherpa-ONNX Custom Modifications

This document records the custom modifications made to sherpa-onnx source code for Intel ARC Graphics GPU acceleration support.

## Overview

The standard sherpa-onnx PyPI package does not include OpenVINO execution provider support. Our custom build added this functionality specifically for Intel ARC Graphics acceleration.

## Modified Files

### 1. `cmake/onnxruntime.cmake`

**Purpose:** Added support for `libonnxruntime_providers_shared.so` library required by OpenVINO execution provider.

**Changes:**
- Added detection and linking of `libonnxruntime_providers_shared` library
- Added environment variable `SHERPA_ONNXRUNTIME_LIB_DIR` support for custom library paths
- Added CMake target for the providers shared library

**Key additions:**
```cmake
# Add providers_shared library for GPU builds
set(location_onnxruntime_providers_shared_lib $ENV{SHERPA_ONNXRUNTIME_LIB_DIR}/libonnxruntime_providers_shared.so)

find_library(location_onnxruntime_providers_shared_lib onnxruntime_providers_shared
  PATHS /lib /usr/lib /usr/local/lib
)

add_library(onnxruntime_providers_shared SHARED IMPORTED)
set_target_properties(onnxruntime_providers_shared PROPERTIES
  IMPORTED_LOCATION ${location_onnxruntime_providers_shared_lib}
)
```

### 2. `sherpa-onnx/csrc/provider.h`

**Purpose:** Added OpenVINO as a supported execution provider type.

**Changes:**
- Added `kOpenVINO = 7` to the `Provider` enum

```cpp
enum class Provider {
  kCPU = 0,       // CpuExecutionProvider
  kCUDA = 1,      // CudaExecutionProvider
  kCoreML = 2,    // CoreMLExecutionProvider
  kXnnpack = 3,   // XnnpackExecutionProvider  
  kNNAPI = 4,     // NnapiExecutionProvider
  kTRT = 5,       // TensorRTExecutionProvider
  kDirectML = 6,  // DmlExecutionProvider
  kOpenVINO = 7,  // OpenVINOExecutionProvider  <-- ADDED
};
```

### 3. `sherpa-onnx/csrc/provider.cc`

**Purpose:** Added string parsing support for "openvino" provider selection.

**Changes:**
- Added "openvino" string mapping to `Provider::kOpenVINO`

```cpp
Provider StringToProvider(std::string s) {
  // ... existing mappings ...
  } else if (s == "openvino") {
    return Provider::kOpenVINO;  // <-- ADDED
  } else {
    // fallback
  }
}
```

### 4. `sherpa-onnx/csrc/session.cc`

**Purpose:** Implemented complete OpenVINO execution provider configuration and initialization.

**Changes:**
- Added full `Provider::kOpenVINO` case in `GetSessionOptionsImpl()`
- Environment variable support for device selection (`OV_DEVICE`)
- Environment variable support for model caching (`OV_CACHE_DIR`) 
- Proper error handling and fallback logic

```cpp
case Provider::kOpenVINO: {
  if (std::find(available_providers.begin(), available_providers.end(),
                "OpenVINOExecutionProvider") != available_providers.end()) {
    std::unordered_map<std::string, std::string> openvino_options;
    
    // Set device type based on environment or default to CPU
    const char* ov_device = std::getenv("OV_DEVICE");
    if (ov_device) {
      openvino_options["device_type"] = ov_device;
    } else {
      openvino_options["device_type"] = "CPU";
    }
    
    openvino_options["precision"] = "FP32";
    
    // Enable caching if directory is set
    const char* ov_cache = std::getenv("OV_CACHE_DIR");
    if (ov_cache) {
      openvino_options["cache_dir"] = ov_cache;
    }
    
    sess_opts.AppendExecutionProvider("OpenVINO", openvino_options);
    SHERPA_ONNX_LOGE("Using OpenVINO with device: %s", openvino_options["device_type"].c_str());
  } else {
    SHERPA_ONNX_LOGE("OpenVINO execution provider not available. Fallback to cpu!");
  }
  break;
}
```

## Impact of Using Standard PyPI Package

By switching to the standard sherpa-onnx PyPI package, we **lose** the following capabilities:

1. **OpenVINO Execution Provider Support** - Cannot use Intel ARC Graphics acceleration
2. **Environment Variable Configuration** - `OV_DEVICE`, `OV_CACHE_DIR` variables ignored
3. **GPU Performance Benefits** - No 1.91x real-time performance improvement
4. **Provider Selection** - Cannot specify `provider="openvino"` in Python API

## Current Status

- **Active:** Standard sherpa-onnx 1.12.11 from PyPI (CPU-only)
- **Archived:** Custom sherpa-onnx build with OpenVINO support in `/tmp/sherpa-onnx/`
- **Available:** Full source code with modifications preserved for future GPU work

## Restoration Process

To restore GPU acceleration capabilities:

1. Navigate to `/tmp/sherpa-onnx/` 
2. Apply the documented modifications above
3. Build with OpenVINO support: `pip install -e .`
4. Install onnxruntime-openvino: `pip install onnxruntime-openvino`
5. Configure environment variables for GPU usage

## Decision Rationale  

The custom modifications were removed in favor of:
- **Simpler maintenance** with standard PyPI packages
- **Reduced complexity** in dependency management  
- **Focus on accuracy** with Vosk as primary engine
- **Preserved knowledge** via complete documentation

The GPU acceleration capability remains fully documented and can be restored when needed for specific performance requirements.