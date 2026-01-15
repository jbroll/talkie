# OpenVINO NPU Build Guide (Intel Core Ultra)

This document describes building OpenVINO with NPU support using the PLUGIN compiler architecture, which separates the MLIR compiler from the NPU driver.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Application                             │
│                    (benchmark_app)                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   OpenVINO Runtime                           │
│              (libopenvino.so, 2026.0.0)                      │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│   NPU Plugin             │    │   MLIR Compiler          │
│ (libopenvino_intel_      │    │ (libnpu_mlir_compiler.so)│
│  npu_plugin.so)          │    │       135 MB             │
└──────────────────────────┘    └──────────────────────────┘
              │                               │
              │         NPU_COMPILER_TYPE     │
              │◄──────────── PLUGIN ─────────►│
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Level Zero Interface                        │
│              (libze_intel_npu.so, 25 MB)                     │
│            linux-npu-driver (no compiler)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kernel Driver                             │
│                     intel_vpu                                │
│                   /dev/accel0                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                Intel Core Ultra NPU                          │
│                  (PCI 8086:7D1D)                             │
└─────────────────────────────────────────────────────────────┘
```

## Why This Architecture?

Two compiler options exist for Intel NPU:

| Option | Description | Size | Pros | Cons |
|--------|-------------|------|------|------|
| **DRIVER** | Compiler embedded in NPU driver | ~25GB build | Single package | Massive build, git-lfs required |
| **PLUGIN** | Compiler in OpenVINO runtime | ~135MB lib | Smaller driver, modular | Requires separate MLIR build |

This guide uses **PLUGIN** mode to avoid the 25GB driver compiler build.

## System Requirements

### Hardware
- Intel Core Ultra processor with NPU (e.g., Core Ultra 7 155H)
- NPU device visible at `/dev/accel0`

### Software
- Linux kernel with `intel_vpu` driver
- CMake 3.20+
- Ninja build system
- Clang 18+ (recommended due to fewer false-positive warnings)
- GCC 14+ has issues with `-Werror=maybe-uninitialized` and `-Werror=dangling-reference`
- 64GB RAM recommended for MLIR compiler build (or use remote build host)

### Verify NPU Hardware
```bash
# Check kernel driver
cat /sys/class/accel/accel0/device/uevent
# Expected: DRIVER=intel_vpu, PCI_ID=8086:7D1D

# Check device permissions
ls -la /dev/accel0
# Ensure read/write access for your user
```

## Build Instructions

### 1. Clone Repositories

```bash
cd ~/pkg

# OpenVINO Runtime
git clone --recursive https://github.com/openvinotoolkit/openvino.git openvino-src
cd openvino-src
git submodule update --init --recursive

# NPU Driver (for Level Zero interface)
cd ~/pkg
git clone https://github.com/intel/linux-npu-driver.git
```

### 2. Build linux-npu-driver (Without Compiler)

```bash
cd ~/pkg/linux-npu-driver
mkdir -p build && cd build

cmake .. \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_NPU_COMPILER_BUILD=OFF

ninja
```

**Output:** `lib/libze_intel_npu.so` (~25MB)

### 3. Extract NPU Compiler Source

The MLIR compiler source is part of the linux-npu-driver repository but fetched separately:

```bash
cd ~/pkg/linux-npu-driver/build

# Configure with compiler to fetch source (but don't build)
cmake .. -DENABLE_NPU_COMPILER_BUILD=ON
# This fetches: compiler/src/npu_compiler (~4.5GB including LLVM)

# The source is now at:
# ~/pkg/linux-npu-driver/build/compiler/src/npu_compiler
```

### 4. Build OpenVINO with MLIR Compiler

**Note:** This build requires ~64GB RAM. Use a remote build host if needed.

```bash
cd ~/pkg/openvino-src
mkdir -p build && cd build

cmake .. \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_CXX_FLAGS="-Wno-error=return-type" \
    -DENABLE_INTEL_NPU=ON \
    -DENABLE_INTEL_CPU=ON \
    -DENABLE_INTEL_GPU=OFF \
    -DENABLE_MLIR_COMPILER=ON \
    -DENABLE_PYTHON=OFF \
    -DENABLE_SAMPLES=ON \
    -DOPENVINO_EXTRA_MODULES=~/pkg/linux-npu-driver/build/compiler/src/npu_compiler

ninja npu_mlir_compiler openvino_intel_npu_plugin benchmark_app
```

**Note:** The `-Wno-error=return-type` flag is needed for clang due to a code issue in `scf_unroll_utils.hpp` where a non-void function doesn't return a value in all control paths.

**Key CMake Options:**

| Option | Value | Purpose |
|--------|-------|---------|
| `ENABLE_INTEL_NPU` | ON | Build NPU plugin |
| `ENABLE_MLIR_COMPILER` | ON | Enable PLUGIN compiler support |
| `ENABLE_INTEL_GPU` | OFF | Avoid OpenCL header conflicts |
| `OPENVINO_EXTRA_MODULES` | path | Point to npu_compiler source |

**Outputs:**
- `bin/intel64/Release/libopenvino.so`
- `bin/intel64/Release/libopenvino_intel_npu_plugin.so`
- `bin/intel64/Release/libnpu_mlir_compiler.so` (135MB)
- `bin/intel64/Release/benchmark_app`

### 5. Remote Build (Optional)

If local machine has insufficient RAM:

```bash
# Transfer source to remote host
tar -cf - -C ~/pkg openvino-src npu_compiler | ssh gpu "tar -xf - -C ~/pkg"

# Build on remote host
ssh gpu "cd ~/pkg/openvino-src/build && ninja npu_mlir_compiler"

# Transfer artifacts back
scp gpu:~/pkg/openvino-src/bin/intel64/Release/libnpu_mlir_compiler.so \
    ~/pkg/openvino-src/bin/intel64/Release/
```

## Usage

### Environment Setup

```bash
export LD_LIBRARY_PATH=~/pkg/linux-npu-driver/build/lib:~/pkg/openvino-src/bin/intel64/Release
```

### Configuration File

Create `/tmp/npu_plugin_config.json`:
```json
{
    "NPU": {
        "NPU_COMPILER_TYPE": "PLUGIN"
    }
}
```

### Run Inference

```bash
# With configuration file
benchmark_app -m model.onnx -d NPU -load_config /tmp/npu_plugin_config.json

# Full example
benchmark_app \
    -m ~/models/mobilenet_v2.onnx \
    -d NPU \
    -niter 100 \
    -shape "[1,3,224,224]" \
    -hint none \
    -load_config /tmp/npu_plugin_config.json
```

### Pre-compile Models (Optional)

```bash
# Compile model to NPU blob
compile_tool \
    -m model.onnx \
    -d NPU \
    -load_config /tmp/npu_plugin_config.json \
    -o model_npu.blob

# Load pre-compiled blob
benchmark_app -m model_npu.blob -d NPU
```

## Verification

### Expected Output
```
[ INFO ] NPU_COMPILER_TYPE: PLUGIN
[ INFO ] NPU_PLATFORM: 3720
[ INFO ] Compile model took 1553.71 ms
[ INFO ] Latency: Median: 1.47 ms
[ INFO ] Throughput: 701.03 FPS
```

### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `libnpu_mlir_compiler.so not found` | Library not in LD_LIBRARY_PATH | Set LD_LIBRARY_PATH correctly |
| `ZE_RESULT_ERROR_UNSUPPORTED_FEATURE` | Using DRIVER compiler without driver compiler | Set `NPU_COMPILER_TYPE=PLUGIN` |
| `libze_intel_npu.so not found` | Driver library missing | Add driver lib path to LD_LIBRARY_PATH |
| `/dev/accel0 permission denied` | No access to NPU device | Add user to appropriate group or use udev rules |

## File Locations Summary

```
~/pkg/
├── openvino-src/
│   └── bin/intel64/Release/
│       ├── libopenvino.so
│       ├── libopenvino_intel_npu_plugin.so
│       ├── libnpu_mlir_compiler.so        # 135MB - PLUGIN compiler
│       └── benchmark_app
│
└── linux-npu-driver/
    └── build/
        └── lib/
            └── libze_intel_npu.so          # 25MB - Level Zero driver
```

## Performance Notes

- First inference includes compilation time (~1.5s for MobileNetV2)
- Subsequent inferences run at full speed
- Use model caching or pre-compilation for production deployments
- NPU excels at transformer and CNN inference workloads

## References

- [OpenVINO Documentation](https://docs.openvino.ai/)
- [Intel NPU Driver](https://github.com/intel/linux-npu-driver)
- [Level Zero Specification](https://spec.oneapi.io/level-zero/latest/)
