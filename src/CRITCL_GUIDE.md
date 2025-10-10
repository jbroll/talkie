# Critcl Wrapper Development Guide

A concise guide for creating Critcl wrappers around C APIs, based on real-world
experience developing a PortAudio binding.

## Quick Setup

Install Critcl from source and set up your environment:
```bash
git clone https://github.com/andreas-kupries/critcl.git
cd critcl && tclsh build.tcl install --prefix ~/.local
export PATH="$HOME/.local/bin:$PATH"
export TCLLIBPATH="$HOME/.local/lib $TCLLIBPATH"
```

Verify your target library is available:
```bash
pkg-config --exists your-library
```

## Basic Package Structure

```tcl
package require critcl 3.1
critcl::cheaders /usr/include/mylib.h
critcl::clibraries -lmylib

namespace eval mylib {}

critcl::ccode {
    #include <tcl.h>
    #include <mylib.h>

    int MyLib_InitPackage(Tcl_Interp *interp) {
        Tcl_CreateObjCommand(interp, "mylib::init", MyLibInitCmd, NULL, NULL);
        return TCL_OK;
    }
}

critcl::cproc mylib::init {} int {
    return mylib_initialize();
}

package provide mylib 1.0
```

Compile with: `critcl -pkg mylib mylib.tcl`

## Core Patterns

### 1. Simple Functions
Use `critcl::cproc` for direct C function wrapping:
```tcl
critcl::cproc mylib::process {int size double rate} int {
    return mylib_process(size, rate);
}
```

### 2. Object-Oriented Wrappers
Create context structures with command dispatchers. Essential components:
- **Context struct**: Store handle, interpreter, command name, state
- **Command dispatcher**: Parse subcommands (`obj process`, `obj close`)
- **Deletion callback**: Clean up resources when object is destroyed
- **Creation command**: Allocate context, create unique command name

Use `sprintf("mylib%d", ++counter)` for unique command names. Always
`Tcl_IncrRefCount()` stored Tcl objects and `Tcl_DecrRefCount()` them in
cleanup.

### 3. Parameter Handling
Create helper functions for safe parameter extraction:
- `GetIntParam()`, `GetDoubleParam()` - wrap `Tcl_GetXxxFromObj()`
- Option parsing loop: `for (i = 1; i < objc; i += 2)` with validation
- Set defaults first, then override with provided options
- Always validate option requires argument

## Memory Management

### Reference Counting
- **Always** increment reference count when storing Tcl objects
- **Always** decrement in cleanup functions
- Use `Tcl_DuplicateObj()` before modifying objects
- Release old objects before storing new ones

### Buffer Management
For real-time data (audio, network):
- **Ring buffers**: Use power-of-2 sizes with bit masking
- **Lock-free**: Single producer, single consumer design
- **Wrap-around handling**: Split writes/reads at buffer boundary
- **malloc/free**: Match every malloc with free, use `ckalloc/ckfree` for Tcl

## Error Handling

Create standardized error reporting:
- **Error functions**: `ReportError()` with consistent messages
- **Library mapping**: Map C library errors to Tcl error codes
- **Resource cleanup**: Always clean up on ALL error paths
- **Step-by-step init**: Initialize incrementally, cleanup on failure

Use `Tcl_SetErrorCode()` for programmatic error handling.

## Threading & Real-Time Processing

### Communication Pattern
1. **Real-time thread**: Minimal work - write to ring buffer, signal main thread
2. **Main thread**: Process data, invoke Tcl callbacks
3. **Signaling**: Use `socketpair()` with file handlers

### Implementation Steps
- Create non-blocking socketpair for notification
- Register `Tcl_CreateFileHandler()` for read end
- Real-time callback: `write()` signal byte to notify
- File handler: drain signals, read ring buffer, invoke Tcl callback

### Critical Points
- Make signaling socket non-blocking
- Limit data processing per event (prevent huge Tcl objects)
- Handle callback errors with `Tcl_BackgroundError()`
- Use `vwait` or event loop to process callbacks

## Testing Strategy

Use `tcltest` for comprehensive testing:

**Essential Tests:**
- Package loading and version
- Object creation/destruction
- Parameter validation (valid and invalid)
- Resource cleanup (create many objects, verify cleanup)
- Error conditions (invalid devices, parameters)

**Real-world Testing:**
- Create streams with actual hardware
- Test with `vwait` to process events properly
- Verify callbacks receive expected data sizes
- Check for memory leaks with repeated operations

## Performance Optimization

**Key Techniques:**
- **Cache objects**: Store common results (`"ok"`, empty dicts)
- **Zero-copy**: Use `Tcl_GetByteArrayFromObj()` for in-place processing
- **Bulk operations**: Process multiple items in single C call
- **Minimize allocations**: Reuse buffers, avoid frequent malloc/free

## Debugging

**Compilation Issues:**
```bash
critcl -keep -show -debug symbols -pkg mylib mylib.tcl
```

**Runtime Debugging:**
- Use `#ifdef DEBUG` with fprintf for conditional logging
- Track allocations with debug wrappers
- Use `DBG()` macro for consistent debug output
- Test error paths explicitly

## Common Pitfalls

1. **Parameter extraction**: Use `Tcl_GetXxxFromObj()`, not `Tcl_GetXxx()`
2. **Reference counting**: Missing `IncrRefCount/DecrRefCount` causes crashes
3. **Thread safety**: Don't access Tcl objects from real-time threads
4. **Error cleanup**: Clean up partially initialized objects
5. **Event loop**: Use `vwait` or `update` to process file handlers

## Essential Best Practices

- **API Design**: Follow Tcl conventions (`-option value`, consistent naming)
- **Error Messages**: Provide specific, actionable error messages
- **Resource Management**: RAII pattern - acquire in constructor, release in destructor
- **Documentation**: Document parameters, return values, and usage examples
- **Testing**: Test error paths, memory management, and performance

## Package Structure Pitfalls

### Missing `package provide` Error
**Problem**: `ERROR: 'package provide' missing in package sources`

**Cause**: CRITCL requires the exact structure from PortAudio pattern:
```tcl
critcl::ccode { /* C code */ }
critcl::cproc PackageName_Init {Tcl_Interp* interp} int { /* init */ }
package provide packagename 1.0
```

**Solution**: Follow the proven PortAudio template exactly:
- Place all C code in single `critcl::ccode` block
- Use `PackageName_InitPackage()` function in C code
- Wire with `critcl::cproc PackageName_Init` calling the C init function
- End with `package provide packagename 1.0`

### Library Extraction Strategy
**Problem**: Complex C libraries (like Vosk) not available as system packages

**Solution**: Extract from official Python wheels:
```bash
wget -O /tmp/lib.whl https://github.com/project/releases/download/v1.0/lib-py3-none-linux_x86_64.whl
cd /tmp && unzip -q lib.whl
cp lib/libname.so ~/.local/lib/
cp src/libname_api.h ~/.local/include/
```

Then configure CRITCL:
```tcl
critcl::cheaders ~/.local/include/libname_api.h
critcl::clibraries -L~/.local/lib -llibname -lm -lstdc++
```
