# OpenVINO XBPS Packaging Strategy (Void Linux)

## Goals
- Build and package **OpenVINO Runtime** for Void Linux using **XBPS**
- Enable **Intel GPU (integrated/Arc)** and **NPU (Core Ultra)** support
- Provide C++ API with minimal dependencies
- Avoid heavyweight tooling (Model Zoo, Jupyter, etc.)
- Avoid shipping large model assets in base packages

---

## Package Decomposition

### 1. openvino-runtime
**Contents**
- Core OpenVINO runtime (`libopenvino.so`)
- C++ headers
- Core runtime utilities

**Build Characteristics**
- CMake-based C++ build
- Python disabled
- Samples and documentation disabled
- No bundled models

**Purpose**
- Minimal inference runtime required by all OpenVINO users

---

### 2. openvino-plugin-cpu
**Contents**
- Intel CPU inference plugin

**Notes**
- Always required as a correctness fallback
- Handles unsupported layers when GPU/NPU execution is incomplete

---

### 3. openvino-plugin-gpu
**Contents**
- Intel GPU plugin (`INTEL_GPU`)
- OpenCL backend (primary)
- Level Zero backend (optional)

**Build Characteristics**
- Requires OpenCL headers and ICD loader
- Optional Level Zero for newer hardware
- Uses system `intel-compute-runtime` (NEO driver)

**Dependencies**
- `ocl-icd` - OpenCL ICD loader
- `intel-compute-runtime` - Intel NEO OpenCL/L0 driver
- `level-zero` - Level Zero loader (optional, for L0 backend)

**Notes**
- Supports Intel HD/UHD/Iris/Arc GPUs
- Good layer coverage for most models
- Often faster than CPU for transformer models

---

### 4. openvino-plugin-npu
**Contents**
- Intel NPU plugin (`INTEL_NPU`)
- Level Zero backend integration

**Build Characteristics**
- Explicit NPU enablement
- Uses system Level Zero libraries
- No bundled firmware or blobs

**Notes**
- Partial graph execution on NPU is expected
- CPU fallback remains active

---

### 5. openvino-tools (optional)
**Contents**
- `benchmark_app`
- `compile_tool`

**Purpose**
- Runtime validation
- Device enumeration
- Layer placement diagnostics

**Notes**
- No Python dependency
- Useful for CI and end-user verification

---

## Explicitly Excluded Components

The following are intentionally **not** packaged:

- **Python bindings** - Use `pip install openvino` in a venv (PyPI wheels work well)
- **Open Model Zoo tools** - Converter requires TensorFlow/PyTorch; use pre-converted models
- **Jupyter notebooks**
- **Pretrained or example models**

---

## Model Handling Strategy

- No models are shipped with any package
- Users supply models manually:
  - Open Model Zoo (OMZ)
  - ONNX models
  - Pre-converted OpenVINO IR (`.xml` / `.bin`)
- Model conversion occurs off-device when necessary

### Recommended Starter Models
- `mobilenet-v3-small`
- `resnet-18`
- Small transformer encoder models (subject to NPU support)

**Recommended size targets:**
- **NPU:** ≤5 million parameters (memory constrained)
- **GPU:** ≤100 million parameters (Arc discrete) / ≤50M (integrated)

---

## Validation Workflow

### C++ (benchmark_app)

```bash
# List available devices
benchmark_app -d MULTI -m model.xml  # Shows device enumeration

# Test specific devices
benchmark_app -d CPU -m model.xml
benchmark_app -d GPU -m model.xml
benchmark_app -d NPU -m model.xml
```

This confirms plugin loading, device availability, and layer assignment.

### Python (via PyPI)

```bash
pip install openvino
python -c "from openvino import Core; print(Core().available_devices)"
```

### Diagnostics

Increase output verbosity:
```bash
export OPENVINO_LOG_LEVEL=INFO
```

### Layer Fallback Behavior
- Unsupported layers automatically fall back to CPU
- Runtime warnings are emitted
- Execution remains correct, with possible performance impact

---

## C++ Usage Model
- Models are external assets (not defined inline)
- Load model, compile for device, run inference

**Typical pattern:**
```cpp

ov::Core core;
auto model = core.read_model("model.xml");

// Target specific device
auto compiled_gpu = core.compile_model(model, "GPU");
auto compiled_npu = core.compile_model(model, "NPU");

// Or use automatic device selection
auto compiled_auto = core.compile_model(model, "AUTO");  // Picks best available
```

---

## Rationale
- Matches Void Linux minimalism and policy
- Keeps packages small and auditable
- Aligns with OpenVINO's intended production deployment model
- Python users can use PyPI wheels (`pip install openvino`)

---

## Build Details

### Repositories

**OpenVINO Runtime:**
- **Repository:** https://github.com/openvinotoolkit/openvino
- **Version:** 2026.0 (current build on dev host)
- **Submodules:** Yes (`git clone --recurse-submodules`)

**NPU Driver (linux-npu-driver):**
- **Repository:** https://github.com/intel/linux-npu-driver
- **Provides:** Level Zero loader + NPU driver (`libze_intel_npu.so`)
- **Also provides:** MLIR compiler source (fetched during configure)

### Build Dependencies
```
cmake
ninja (or make)
gcc (or clang - see notes)
pkg-config
tbb-devel
pugixml-devel
protobuf-devel
flatbuffers-devel
ocl-icd-devel      # GPU plugin
opencl-headers     # GPU plugin
```

### Compiler Notes

From `NPU-BUILD-GUIDE.md`:
- **GCC 14+** has issues with `-Werror=maybe-uninitialized` and `-Werror=dangling-reference`
- **Clang 18+** recommended for NPU MLIR compiler build
- If using Clang, add `-Wno-error=return-type` for MLIR code issue
- **64GB RAM** recommended for MLIR compiler build (or use remote build host)

### CMake Configuration (from working build)

**linux-npu-driver (build first):**
```bash
cd linux-npu-driver && mkdir build && cd build
cmake .. -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_NPU_COMPILER_BUILD=ON   # Fetches MLIR source
ninja                                 # Builds libze_intel_npu.so + level-zero
```

**OpenVINO (build second):**
```bash
cd openvino-src && mkdir build && cd build
cmake .. -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_INTEL_CPU=ON \
    -DENABLE_INTEL_GPU=ON \
    -DENABLE_INTEL_NPU=ON \
    -DENABLE_MLIR_COMPILER=ON \
    -DENABLE_PYTHON=OFF \
    -DENABLE_SAMPLES=ON \
    -DENABLE_DOCS=OFF \
    -DENABLE_AUTO=ON \
    -DENABLE_AUTO_BATCH=ON \
    -DENABLE_HETERO=ON \
    -DOPENVINO_EXTRA_MODULES=/path/to/linux-npu-driver/build/compiler/src/npu_compiler
ninja
```

### Dependency Graph

```
linux-npu-driver
└── (no deps, provides libze_loader.so + libze_intel_npu.so)

openvino-runtime
├── tbb
├── pugixml
├── protobuf
└── linux-npu-driver (for Level Zero loader)

openvino-plugin-cpu
└── openvino-runtime

openvino-plugin-gpu
├── openvino-runtime
├── ocl-icd
└── intel-compute-runtime (runtime, for NEO OpenCL driver)

openvino-plugin-npu
├── openvino-runtime
├── linux-npu-driver (for libze_intel_npu.so)
└── openvino-npu-compiler (libnpu_mlir_compiler.so, 135 MB)

openvino-tools
└── openvino-runtime
```

### Library Inventory (from actual build)

**linux-npu-driver outputs** (`~/pkg/linux-npu-driver/build/lib/`):
```
libze_intel_npu.so.1.28.0      # NPU Level Zero driver (25 MB)
libze_loader.so.1.24.2         # Level Zero loader
libze_validation_layer.so      # Debug layer
libze_tracing_layer.so         # Tracing layer
```

**OpenVINO outputs** (`~/pkg/openvino-src/bin/intel64/Release/`):
```
# Core runtime
libopenvino.so                 # Main runtime
libopenvino_c.so               # C API

# Plugins
libopenvino_intel_cpu_plugin.so
libopenvino_intel_gpu_plugin.so
libopenvino_intel_npu_plugin.so
libopenvino_auto_plugin.so
libopenvino_auto_batch_plugin.so
libopenvino_hetero_plugin.so

# NPU compiler (PLUGIN mode)
libnpu_mlir_compiler.so        # 135 MB - MLIR compiler

# Frontends
libopenvino_onnx_frontend.so
libopenvino_tensorflow_frontend.so
libopenvino_tensorflow_lite_frontend.so
libopenvino_pytorch_frontend.so
libopenvino_jax_frontend.so
libopenvino_paddle_frontend.so
libopenvino_ir_frontend.so

# Bundled (may use system instead)
libOpenCL.so                   # Bundled OpenCL
libze_loader.so                # Bundled Level Zero loader

# Tools
benchmark_app
compile_tool
```

---

## Void Prerequisites Check

**Packages in Void repos:**

| Package | Status | Notes |
|---------|--------|-------|
| `tbb` | ✓ | Intel TBB |
| `pugixml` | ✓ | XML parser |
| `protobuf` | ✓ | Serialization |
| `flatbuffers` | ✓ | v1.12.0 (may need update) |
| `ocl-icd` | ✓ | OpenCL loader |
| `level-zero` | ✗ | **Built by linux-npu-driver** |
| `intel-compute-runtime` | ✗ | **Needs packaging (GPU only)** |

**Key insight from dev host build:**
- `linux-npu-driver` builds its own Level Zero loader (`libze_loader.so`)
- NPU support does NOT require `intel-compute-runtime`
- GPU (OpenCL) support requires `intel-compute-runtime` (NEO driver)

**Packaging order:**
1. `linux-npu-driver` - Provides Level Zero loader + NPU driver
2. `openvino` - Depends on linux-npu-driver for NPU
3. `intel-compute-runtime` (optional) - Only for GPU OpenCL backend

---

## NPU Compiler Architecture

Two compiler options exist for Intel NPU:

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **DRIVER** | Compiler embedded in NPU driver | Single package | 25GB build, git-lfs required |
| **PLUGIN** | Compiler in OpenVINO (libnpu_mlir_compiler.so) | Modular, smaller driver | 135MB separate lib |

**Recommended: PLUGIN mode** (used on dev host)
- NPU driver stays small (~25 MB)
- MLIR compiler built as part of OpenVINO
- Runtime config: `NPU_COMPILER_TYPE=PLUGIN`

**Runtime configuration** (`/tmp/npu_plugin_config.json`):
```json
{
    "NPU": {
        "NPU_COMPILER_TYPE": "PLUGIN"
    }
}
```

---

## Subpackage Strategy

**Separate source packages:**

```
linux-npu-driver (source package)
├── linux-npu-driver        # libze_intel_npu.so (NPU driver)
└── level-zero-loader       # libze_loader.so (L0 loader)

openvino (source package)
├── openvino-runtime        # main package (libopenvino.so)
├── openvino-runtime-devel  # headers, cmake files
├── openvino-plugin-cpu     # always installed with runtime
├── openvino-plugin-gpu     # requires intel-compute-runtime
├── openvino-plugin-npu     # requires linux-npu-driver
├── openvino-npu-compiler   # libnpu_mlir_compiler.so (135 MB)
├── openvino-frontends      # ONNX, TF, PyTorch, etc.
└── openvino-tools          # benchmark_app, compile_tool
```

**Notes:**
- `linux-npu-driver` must be packaged first (provides Level Zero)
- NPU compiler is large (135 MB) - separate package recommended
- Consider bundling CPU plugin with runtime (always needed as fallback)

---

## Reference Documentation

Local build guides on this host:
- `tools/NPU-BUILD-GUIDE.md` - Complete NPU build instructions
- `tools/NPU-GEC-BENCHMARK.md` - NPU vs CPU benchmarks for GEC models
- `docs/sherpa-onnx-arc/SHERPA_ONNX_GPU_BUILD.md` - GPU (Arc) build notes
- `tools/AI-MODELS-RESEARCH.md` - Model research and CTranslate2 integration