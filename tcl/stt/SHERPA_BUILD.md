# Building Sherpa-ONNX Libraries with -fPIC

## Quick Build Instructions

```bash
# Clone and prepare
cd /tmp
git clone https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx

# Configure with -fPIC for shared library compatibility
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$HOME/.local \
      -DCMAKE_C_FLAGS="-fPIC" \
      -DCMAKE_CXX_FLAGS="-fPIC" \
      -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
      -DSHERPA_ONNX_ENABLE_TESTS=OFF \
      -DSHERPA_ONNX_ENABLE_CHECK=OFF \
      -DBUILD_SHARED_LIBS=OFF \
      ..

# Build and install
make -j$(nproc)
make install
```

## Key Points

- **-fPIC is essential** for linking static libraries into shared libraries (required for Tcl extensions)
- **Static libraries** (`BUILD_SHARED_LIBS=OFF`) avoid Python wheel conflicts
- **Install to ~/.local** keeps libraries separate from system packages
- **Disable Python/tests** for faster, cleaner build

## Verify Installation

```bash
ls ~/.local/lib/libsherpa-onnx*.a    # Static libraries
ls ~/.local/include/sherpa-onnx*.h   # Headers
```

The resulting libraries can then be used with the Tcl STT framework without the initialization conflicts that occurred with Python wheel libraries.

## Architecture Notes

This build approach resolves the memory corruption issues that occurred when using Sherpa-ONNX libraries extracted from Python wheels. The Python wheel libraries contained pre-compiled binaries with specific symbol visibility and dependencies that conflicted with Vosk's static initialization during `_dl_init`.

By building from source with `-fPIC`, we ensure:
1. Proper position-independent code for shared library linking
2. Clean static libraries without Python-specific artifacts
3. Compatible symbol management for use with other speech engines