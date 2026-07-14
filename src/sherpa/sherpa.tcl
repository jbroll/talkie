# sherpa.tcl - Critcl sherpa-onnx streaming ASR Tcl package
package require critcl 3.1

critcl::cflags -I$::env(HOME)/.local/include
critcl::clibraries -L$::env(HOME)/.local/lib -lsherpa-onnx-c-api -lonnxruntime -lm -lstdc++
critcl::clibraries -L/home/john/pkg/install/lib -ltclstub

namespace eval sherpa {}

critcl::ccode {
#include <tcl.h>
#include <sherpa-onnx/c-api/c-api.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
}

critcl::cproc sherpa::version {} char* {
    return (char*)SherpaOnnxGetVersionStr();
}

package provide sherpa 1.0
