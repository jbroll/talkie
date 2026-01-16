# OpenVINO XBPS Packaging Strategy (Void Linux)

## Goals
- Build and package **OpenVINO Runtime** for Void Linux using **XBPS**
- Enable **Intel NPU (Core Ultra)** support
- Minimize dependencies and avoid Python-heavy workflows
- Provide **C++-only, offline-usable** examples
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
- Handles unsupported layers when NPU execution is incomplete

---

### 3. openvino-plugin-npu
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

### 4. openvino-tools (optional)
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

- Python bindings (`openvino-python`)
- Open Model Zoo downloader/converter tools
- Jupyter notebooks
- Pretrained or example models

These may be introduced later as optional packages if required.

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

**Recommended size target:** ≤5 million parameters for efficient NPU execution

---

## Validation Workflow (C++ / No Python)

Basic runtime validation:

```bash
benchmark_app -d NPU -m model.xml

This confirms:

    Plugin loading

    Device availability

    Layer assignment and fallback behavior

Increase diagnostic output:

OPENVINO_LOG_LEVEL=INFO

Layer Fallback Behavior

    Unsupported layers automatically fall back to CPU

    Runtime warnings are emitted

    Execution remains correct, with possible performance impact

C++ Usage Model

    Models are external assets

    Computational graphs are not defined inline in C++

    Typical usage pattern:

ov::Core core;
auto model = core.read_model("model.xml");
auto compiled_model = core.compile_model(model, "INTEL_NPU");

Rationale

    Matches Void Linux minimalism and policy

    Avoids Python dependency explosion

    Keeps packages small and auditable

    Aligns with OpenVINO’s intended production deployment model