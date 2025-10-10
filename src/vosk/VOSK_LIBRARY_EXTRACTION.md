# Extracting Vosk Library from Python Wheel

This guide documents the process of obtaining the Vosk C library and headers
without requiring Python dependencies, by extracting them from the official
Python wheel package.

## Why This Approach?

- **No Python Dependencies**: Get Vosk without installing Python packages
- **Official Binaries**: Use precompiled libraries from the Vosk team
- **No Complex Build**: Avoid building Vosk from source with Kaldi dependencies
- **Cross-Platform**: Works on any platform with available wheel

## Step-by-Step Extraction Process

### 1. Download the Python Wheel

```bash
# Download the official Vosk wheel for your platform
wget -O /tmp/vosk.whl \
  https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-0.3.45-py3-none-linux_x86_64.whl

# Verify the download
file /tmp/vosk.whl
# Output: /tmp/vosk.whl: Zip archive data, at least v2.0 to extract
```

### 2. Extract the Wheel Contents

Python wheels are ZIP archives that can be extracted with standard tools:

```bash
cd /tmp
unzip -q vosk.whl

# Examine the structure
find . -name "*.so" -o -name "*.h" | head -10
```

### 3. Locate the Library and Headers

The extraction reveals the key files:

```bash
# The main shared library (26MB compiled Vosk)
ls -la vosk/libvosk.so
# -rwxr-xr-x 1 user user 25986496 vosk/libvosk.so

# The C API header from the source tree
ls -la vosk-api-0.3.45/src/vosk_api.h
# -rw-rw-r-- 1 user user 12445 vosk-api-0.3.45/src/vosk_api.h
```

### 4. Install to System Location

```bash
# Create directories if needed
mkdir -p ~/.local/lib ~/.local/include

# Install the shared library
cp vosk/libvosk.so ~/.local/lib/

# Install the header
cp vosk-api-0.3.45/src/vosk_api.h ~/.local/include/

# Verify installation
ls -la ~/.local/lib/libvosk.so ~/.local/include/vosk_api.h
```

### 5. Verify Library Dependencies

```bash
# Check what the library depends on (should be minimal)
ldd ~/.local/lib/libvosk.so | head -5
# Output:
#   linux-vdso.so.1 (0x000076e2a8f80000)
#   libstdc++.so.6 => /lib/x86_64-linux-gnu/libstdc++.so.6
#   libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6
#   libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1
#   libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6
```

## What This Gives You

### Complete Vosk C Library
- **libvosk.so**: Full speech recognition engine (26MB)
- **All dependencies included**: No need for separate Kaldi installation
- **Production ready**: Same library used by Python Vosk package

### C API Headers
- **vosk_api.h**: Complete C API definition (12KB)
- **All function signatures**: Model loading, recognition, configuration
- **Type definitions**: VoskModel, VoskRecognizer structures

## Key Functions Available

After extraction, you have access to the complete Vosk C API:

```c
// Model management
VoskModel* vosk_model_new(const char *model_path);
void vosk_model_free(VoskModel *model);

// Recognizer management
VoskRecognizer* vosk_recognizer_new(VoskModel *model, float sample_rate);
void vosk_recognizer_free(VoskRecognizer *recognizer);

// Speech recognition
int vosk_recognizer_accept_waveform(VoskRecognizer *recognizer, const char *data, int length);
const char* vosk_recognizer_result(VoskRecognizer *recognizer);
const char* vosk_recognizer_partial_result(VoskRecognizer *recognizer);
const char* vosk_recognizer_final_result(VoskRecognizer *recognizer);

// Configuration
void vosk_recognizer_set_max_alternatives(VoskRecognizer *recognizer, int max_alternatives);
void vosk_recognizer_reset(VoskRecognizer *recognizer);
void vosk_set_log_level(int log_level);
```

## Platform-Specific Wheels

Choose the appropriate wheel for your platform:

```bash
# Linux x86_64 (most common)
wget https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-0.3.45-py3-none-linux_x86_64.whl

# Linux ARM64 (Raspberry Pi 4, etc.)
wget https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-0.3.45-py3-none-linux_aarch64.whl

# Linux ARM (Raspberry Pi 3, etc.)
wget https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-0.3.45-py3-none-linux_armv7l.whl

# macOS (Intel)
wget https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-0.3.45-py3-none-macosx_10_9_x86_64.whl

# macOS (Apple Silicon)
wget https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-0.3.45-py3-none-macosx_11_0_arm64.whl
```

## Integration with CRITCL

Once extracted, configure CRITCL to use the library:

```tcl
# In your .tcl binding file:
critcl::cheaders ~/.local/include/vosk_api.h
critcl::clibraries -L~/.local/lib -lvosk -lm -lstdc++
```

## Advantages of This Approach

### ✅ **No Build Complexity**
- Skip complicated Kaldi compilation
- No need to manage build dependencies
- Works out of the box

### ✅ **Official Distribution**
- Same binaries used by Python Vosk
- Maintained by Vosk team
- Regular security updates

### ✅ **Minimal Dependencies**
- Only requires standard C++ runtime
- No Python interpreter needed
- Clean system integration

### ✅ **Version Control**
- Pin to specific Vosk version
- Reproducible builds
- Easy upgrades

## Alternative Sources

If the GitHub releases are unavailable, you can also extract from PyPI:

```bash
# Download from PyPI
pip download --no-deps vosk==0.3.45
unzip vosk-0.3.45-py3-none-linux_x86_64.whl
```

## Verification

Test that the extracted library works:

```bash
# Set library path
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# Quick test with a C program
cat > test_vosk.c << 'EOF'
#include <stdio.h>
#include "vosk_api.h"

int main() {
    vosk_set_log_level(-1);
    printf("Vosk library loaded successfully\n");
    return 0;
}
EOF

gcc -I~/.local/include -L~/.local/lib -lvosk -lstdc++ -o test_vosk test_vosk.c
./test_vosk
```

## Troubleshooting

### Library Not Found
```bash
# Add to your environment
echo 'export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Symbol Errors
- Ensure you're linking with `-lstdc++` and `-lm`
- Check that the wheel matches your platform architecture

### Permission Issues
```bash
# Make library executable
chmod +x ~/.local/lib/libvosk.so
```

This extraction method provides a clean, dependency-free way to obtain the Vosk
library for use with CRITCL bindings, avoiding the complexity of building from
source while using official, tested binaries.
