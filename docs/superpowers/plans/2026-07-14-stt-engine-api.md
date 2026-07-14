# STT Engine API + sherpa-onnx Binding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-process sherpa-onnx critcl STT binding (streaming Zipformer transducer) and formalize a common `stt::` engine contract — with an end-of-utterance signal — that Vosk, sherpa-onnx, whisper.cpp, and OpenVINO GenAI can all implement.

**Architecture:** A new critcl package `src/sherpa/` wraps `sherpa-onnx/c-api/c-api.h`, exposing a Vosk-shaped handle (`process`/`final-result`/`reset`). `process` returns `{partial, endpoint}`. `src/engine.tcl` gains thin `stt::` dispatch procs (one critcl-vs-coprocess branch instead of five), registry capability flags (`endpointing`, `emits_partials`), and capability-driven finalization: `self`-endpoint engines finalize on the engine's `endpoint:1`; `external` engines finalize via partial-stability OR the existing energy-silence timer.

**Tech Stack:** Tcl 9, critcl 3.1 (`/home/john/bin/critcl`), sherpa-onnx C API (prebuilt shared libs), onnxruntime (bundled with sherpa-onnx), Zipformer streaming transducer ONNX model (already staged).

## Global Constraints

- critcl binary: `/home/john/bin/critcl` (Tcl 9). Never `/usr/bin/critcl`.
- Tcl stubs link: `critcl::clibraries -L/home/john/pkg/install/lib -ltclstub`. Never `-ltclstub8.6`.
- Do NOT use `critcl::cproc` with a `Tcl_Obj*` return type (segfaults under Tcl 9). Use `critcl::ccode` + `Tcl_CreateObjCommand`, like `src/vosk/vosk.tcl`.
- sherpa-onnx `AcceptWaveform` requires **float32** PCM in `[-1,1]`; convert int16 LE → float internally (`sample / 32768.0`).
- Model staged at: `models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26/` (encoder/decoder/joiner `.int8.onnx` + `tokens.txt`). Use the `.int8.onnx` variants.
- New engine registry name: `sherpa-onnx` (coexists with existing Python `sherpa` coprocess).
- Headers → `~/.local/include`, shared libs → `~/.local/lib` (Vosk convention).
- Commit after each task. Branch is `stt-engine-api` (already created).

---

### Task 1: Install the sherpa-onnx C shared library

**Files:**
- Create: `~/.local/include/sherpa-onnx/c-api/c-api.h` (installed)
- Create: `~/.local/lib/libsherpa-onnx-c-api.so`, `~/.local/lib/libonnxruntime.so*` (installed)
- Create: `tools/install-sherpa-onnx-lib.sh` (repeatable installer)

**Interfaces:**
- Produces: header at `$HOME/.local/include/sherpa-onnx/c-api/c-api.h`; libs at `$HOME/.local/lib/`. The binding (Task 2) compiles against these.

- [ ] **Step 1: Find the latest versioned software release** (the `vX.Y.Z` tags carry `sherpa-onnx-vX.Y.Z-linux-x64-shared.tar.bz2`; the `asr-models-*` tags do not).

```bash
curl -sSL "https://api.github.com/repos/k2-fsa/sherpa-onnx/releases?per_page=40" \
  | grep -oE '"browser_download_url": "[^"]*linux-x64-shared\.tar\.bz2"' \
  | head -3
```
Expected: one or more URLs like `.../download/v1.10.x/sherpa-onnx-v1.10.x-linux-x64-shared.tar.bz2`.

- [ ] **Step 2: Write the installer script** `tools/install-sherpa-onnx-lib.sh`

```bash
#!/usr/bin/env bash
# Install prebuilt sherpa-onnx C shared library + headers into ~/.local
set -euo pipefail
URL="${1:?usage: install-sherpa-onnx-lib.sh <linux-x64-shared.tar.bz2 URL>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading $URL"
curl -sSL "$URL" -o "$TMP/sherpa.tar.bz2"
tar -xjf "$TMP/sherpa.tar.bz2" -C "$TMP"
SRC="$(find "$TMP" -maxdepth 1 -type d -name 'sherpa-onnx-*')"
mkdir -p "$HOME/.local/lib" "$HOME/.local/include"
cp -av "$SRC"/lib/. "$HOME/.local/lib/"
cp -av "$SRC"/include/. "$HOME/.local/include/"
echo "Installed sherpa-onnx libs to ~/.local/lib and headers to ~/.local/include"
```

- [ ] **Step 3: Run the installer** with the URL from Step 1

```bash
chmod +x tools/install-sherpa-onnx-lib.sh
tools/install-sherpa-onnx-lib.sh "<URL from step 1>"
```
Expected: files copied, no error.

- [ ] **Step 4: Verify header + library symbols present**

```bash
test -f "$HOME/.local/include/sherpa-onnx/c-api/c-api.h" && echo "HEADER OK"
nm -D "$HOME/.local/lib/libsherpa-onnx-c-api.so" | grep -E "SherpaOnnxCreateOnlineRecognizer|SherpaOnnxOnlineStreamIsEndpoint" | head
```
Expected: `HEADER OK` and both symbols listed.

- [ ] **Step 5: Record the exact struct/field names** the binding must match (the API is stable but verify). Read the installed header and confirm these names exist: `SherpaOnnxOnlineRecognizerConfig`, `SherpaOnnxFeatureConfig` (`sample_rate`, `feature_dim`), `SherpaOnnxOnlineModelConfig` (`transducer`, `tokens`, `num_threads`, `provider`), `SherpaOnnxOnlineTransducerModelConfig` (`encoder`, `decoder`, `joiner`), `enable_endpoint`, `rule1_min_trailing_silence`, `rule2_min_trailing_silence`, `rule3_min_utterance_length`.

```bash
grep -nE "SherpaOnnxOnlineTransducerModelConfig|SherpaOnnxOnlineModelConfig|SherpaOnnxOnlineRecognizerConfig|SherpaOnnxFeatureConfig|enable_endpoint|rule1_min_trailing_silence" "$HOME/.local/include/sherpa-onnx/c-api/c-api.h"
```
Expected: struct definitions and fields listed. **If any field name differs, use the header's actual names in Task 3's C code.**

- [ ] **Step 6: Commit**

```bash
git add tools/install-sherpa-onnx-lib.sh
git commit -m "build: add sherpa-onnx C library installer"
```

---

### Task 2: critcl binding skeleton that loads the library

**Files:**
- Create: `src/sherpa/sherpa.tcl`
- Create: `src/sherpa/Makefile`
- Test: `src/sherpa/tests/test_load.tcl`

**Interfaces:**
- Produces: package `sherpa` providing `sherpa::version` (returns the sherpa-onnx version string). Task 3 extends this same file.

- [ ] **Step 1: Write the Makefile** `src/sherpa/Makefile`

```makefile
# Simple Makefile for sherpa-onnx package

.PHONY: all clean test

CRITCL = /home/john/bin/critcl

all:
	$(CRITCL) -pkg sherpa.tcl

clean:
	rm -rf lib

test: all
	LD_LIBRARY_PATH=$(HOME)/.local/lib tclsh tests/test_load.tcl
```

- [ ] **Step 2: Write the binding skeleton** `src/sherpa/sherpa.tcl`

```tcl
# sherpa.tcl - Critcl sherpa-onnx streaming ASR Tcl package
package require critcl 3.1

critcl::cheaders $::env(HOME)/.local/include/sherpa-onnx/c-api/c-api.h
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
```

- [ ] **Step 3: Write the load test** `src/sherpa/tests/test_load.tcl`

```tcl
lappend auto_path [file join [file dirname [info script]] .. lib]
package require sherpa
set v [sherpa::version]
if {$v eq ""} { puts "FAIL: empty version"; exit 1 }
puts "PASS: sherpa-onnx version = $v"
exit 0
```

- [ ] **Step 4: Build and run the load test**

```bash
cd src/sherpa && make test
```
Expected: `PASS: sherpa-onnx version = ...`.
(If `SherpaOnnxGetVersionStr` is absent in this release, use any other exported symbol confirmed in Task 1 Step 4; the point is that the library links and loads.)

- [ ] **Step 5: Commit**

```bash
git add src/sherpa/sherpa.tcl src/sherpa/Makefile src/sherpa/tests/test_load.tcl
git commit -m "feat: sherpa-onnx critcl binding skeleton (loads library)"
```

---

### Task 3: Recognizer — create, process→{partial,endpoint}, final-result, reset

**Files:**
- Modify: `src/sherpa/sherpa.tcl` (add ccode structs + commands before `package provide`)
- Test: `src/sherpa/tests/test_recognize.tcl`

**Interfaces:**
- Consumes: sherpa-onnx C API verified in Task 1.
- Produces:
  - `sherpa::create_recognizer -encoder <p> -decoder <p> -joiner <p> -tokens <p> -rate <hz>` → recognizer command name.
  - recognizer `process <int16-bytes>` → JSON `{"partial":<str>,"endpoint":0|1}`.
  - recognizer `final-result` → JSON `{"text":<str>}` (and resets the stream).
  - recognizer `reset` → `ok`.
  - recognizer `close` → deletes command.

- [ ] **Step 1: Write the failing recognition test** `src/sherpa/tests/test_recognize.tcl`

```tcl
lappend auto_path [file join [file dirname [info script]] .. lib]
package require sherpa

set model_dir [file normalize [file join [file dirname [info script]] \
    ../../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26]]

set rec [sherpa::create_recognizer \
    -encoder [file join $model_dir encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx] \
    -decoder [file join $model_dir decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx] \
    -joiner  [file join $model_dir joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx] \
    -tokens  [file join $model_dir tokens.txt] \
    -rate 16000]

# Read a 16kHz mono 16-bit PCM WAV, skip 44-byte header
set f [open [file join $model_dir test_wavs 0.wav] rb]
set wav [read $f]
close $f
set pcm [string range $wav 44 end]

# Feed in 3200-byte (100ms) chunks; collect partial + endpoint
set saw_endpoint 0
set last_partial ""
for {set i 0} {$i < [string length $pcm]} {incr i 3200} {
    set chunk [string range $pcm $i [expr {$i+3199}]]
    set r [$rec process $chunk]
    if {[dict get $r endpoint]} { set saw_endpoint 1 }
    set last_partial [dict get $r partial]
}
set final [$rec final-result]
set text [string trim [dict get $final text]]
$rec close

puts "partial='$last_partial' final='$text' endpoint=$saw_endpoint"
if {[string length $text] < 3} { puts "FAIL: transcript too short"; exit 1 }
puts "PASS"
exit 0
```

Note: `$rec process` returns a JSON string; the test uses `dict get` on it, so `process`/`final-result` must return valid Tcl-dict-compatible JSON (flat `{"partial":"...","endpoint":0}`). Since flat JSON with string values is a valid Tcl dict only if quoted consistently, the C code emits a **Tcl dict** (via `Tcl_NewDictObj`) rendered as a string, matching how the test consumes it. (Vosk returns raw JSON parsed elsewhere with `json::json2dict`; here we return a dict object directly for simplicity, and Task 5's `stt::process` normalizes both.)

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/sherpa && make all && LD_LIBRARY_PATH=$HOME/.local/lib tclsh tests/test_recognize.tcl
```
Expected: FAIL — `invalid command name "sherpa::create_recognizer"`.

- [ ] **Step 3: Implement the recognizer** — insert this into `src/sherpa/sherpa.tcl` inside a `critcl::ccode { ... }` block placed AFTER the existing `#include` ccode block and BEFORE `package provide`, then add the `cinit`.

```tcl
critcl::ccode {

typedef struct {
    const SherpaOnnxOnlineRecognizer *recognizer;
    const SherpaOnnxOnlineStream *stream;
    Tcl_Interp *interp;
    Tcl_Obj *cmdname;
    int sample_rate;
    int closed;
} SherpaCtx;

static void sherpa_delete(ClientData cd) {
    SherpaCtx *ctx = (SherpaCtx*)cd;
    if (!ctx) return;
    ctx->closed = 1;
    if (ctx->stream)     { SherpaOnnxDestroyOnlineStream(ctx->stream); ctx->stream = NULL; }
    if (ctx->recognizer) { SherpaOnnxDestroyOnlineRecognizer(ctx->recognizer); ctx->recognizer = NULL; }
    if (ctx->cmdname)    { Tcl_DecrRefCount(ctx->cmdname); ctx->cmdname = NULL; }
    ckfree((char*)ctx);
}

/* Drain the decoder while the stream has enough frames. */
static void sherpa_decode_ready(SherpaCtx *ctx) {
    while (SherpaOnnxIsOnlineStreamReady(ctx->recognizer, ctx->stream)) {
        SherpaOnnxDecodeOnlineStream(ctx->recognizer, ctx->stream);
    }
}

static const char *sherpa_result_text(SherpaCtx *ctx) {
    const SherpaOnnxOnlineRecognizerResult *res =
        SherpaOnnxGetOnlineStreamResult(ctx->recognizer, ctx->stream);
    static char buf[4096];
    buf[0] = '\0';
    if (res && res->text) { strncpy(buf, res->text, sizeof(buf)-1); buf[sizeof(buf)-1]='\0'; }
    if (res) SherpaOnnxDestroyOnlineRecognizerResult(res);
    return buf;
}

static int SherpaRecObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    SherpaCtx *ctx = (SherpaCtx*)cd;
    if (!ctx || ctx->closed) { Tcl_AppendResult(interp, "recognizer closed", NULL); return TCL_ERROR; }
    if (objc < 2) { Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?"); return TCL_ERROR; }
    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub, "process") == 0) {
        if (objc != 3) { Tcl_WrongNumArgs(interp, 2, objv, "audio_data"); return TCL_ERROR; }
        Tcl_Size length;
        unsigned char *data = Tcl_GetByteArrayFromObj(objv[2], &length);
        if (!data || length < 2) { Tcl_AppendResult(interp, "invalid audio data", NULL); return TCL_ERROR; }
        int n = length / 2;
        float *samples = (float*)ckalloc(n * sizeof(float));
        const short *pcm = (const short*)data;
        for (int i = 0; i < n; i++) samples[i] = pcm[i] / 32768.0f;
        SherpaOnnxOnlineStreamAcceptWaveform(ctx->stream, ctx->sample_rate, samples, n);
        ckfree((char*)samples);
        sherpa_decode_ready(ctx);
        int endpoint = SherpaOnnxOnlineStreamIsEndpoint(ctx->recognizer, ctx->stream);
        const char *text = sherpa_result_text(ctx);
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("partial", -1), Tcl_NewStringObj(text, -1));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("endpoint", -1), Tcl_NewIntObj(endpoint ? 1 : 0));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "final-result") == 0) {
        sherpa_decode_ready(ctx);
        const char *text = sherpa_result_text(ctx);
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("text", -1), Tcl_NewStringObj(text, -1));
        SherpaOnnxOnlineStreamReset(ctx->recognizer, ctx->stream);
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "reset") == 0) {
        SherpaOnnxOnlineStreamReset(ctx->recognizer, ctx->stream);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }
    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

static int SherpaCreateRecognizerCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    const char *encoder=NULL,*decoder=NULL,*joiner=NULL,*tokens=NULL;
    int sample_rate = 16000;
    for (int i = 1; i < objc; i++) {
        const char *opt = Tcl_GetString(objv[i]);
        if      (strcmp(opt,"-encoder")==0 && i+1<objc) encoder = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-decoder")==0 && i+1<objc) decoder = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-joiner")==0  && i+1<objc) joiner  = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-tokens")==0  && i+1<objc) tokens  = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-rate")==0    && i+1<objc) { Tcl_Size t; Tcl_GetSizeIntFromObj(interp,objv[++i],&t); sample_rate=(int)t; }
        else { Tcl_AppendResult(interp,"unknown option ",opt,NULL); return TCL_ERROR; }
    }
    if (!encoder||!decoder||!joiner||!tokens) { Tcl_AppendResult(interp,"missing -encoder/-decoder/-joiner/-tokens",NULL); return TCL_ERROR; }

    SherpaOnnxOnlineRecognizerConfig config;
    memset(&config, 0, sizeof(config));
    config.feat_config.sample_rate = sample_rate;
    config.feat_config.feature_dim = 80;
    config.model_config.transducer.encoder = encoder;
    config.model_config.transducer.decoder = decoder;
    config.model_config.transducer.joiner  = joiner;
    config.model_config.tokens = tokens;
    config.model_config.num_threads = 2;
    config.model_config.provider = "cpu";
    config.model_config.debug = 0;
    config.decoding_method = "greedy_search";
    config.max_active_paths = 4;
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = 2.4f;
    config.rule2_min_trailing_silence = 1.2f;
    config.rule3_min_utterance_length = 20.0f;

    const SherpaOnnxOnlineRecognizer *recognizer = SherpaOnnxCreateOnlineRecognizer(&config);
    if (!recognizer) { Tcl_AppendResult(interp,"failed to create sherpa-onnx recognizer",NULL); return TCL_ERROR; }
    const SherpaOnnxOnlineStream *stream = SherpaOnnxCreateOnlineStream(recognizer);
    if (!stream) { SherpaOnnxDestroyOnlineRecognizer(recognizer); Tcl_AppendResult(interp,"failed to create stream",NULL); return TCL_ERROR; }

    SherpaCtx *ctx = (SherpaCtx*)ckalloc(sizeof(SherpaCtx));
    memset(ctx,0,sizeof(*ctx));
    ctx->recognizer = recognizer; ctx->stream = stream; ctx->interp = interp; ctx->sample_rate = sample_rate; ctx->closed = 0;

    static int counter = 0;
    char namebuf[64];
    sprintf(namebuf,"sherpa_recognizer%d",++counter);
    Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf,-1);
    Tcl_IncrRefCount(nameObj);
    ctx->cmdname = nameObj;
    Tcl_CreateObjCommand(interp, namebuf, SherpaRecObjCmd, (ClientData)ctx, sherpa_delete);
    Tcl_SetObjResult(interp, nameObj);
    return TCL_OK;
}

}
```

And add the `cinit` (registers the create command) before `package provide`:

```tcl
critcl::cinit {
    Tcl_CreateObjCommand(interp, "sherpa::create_recognizer", SherpaCreateRecognizerCmd, NULL, NULL);
} ""
```

(If Task 1 Step 5 found different field names — e.g. `enable_endpoint_detection` — substitute them here. Also confirm the transducer sub-struct path is `config.model_config.transducer.{encoder,decoder,joiner}`.)

- [ ] **Step 4: Build and run the test to verify it passes**

```bash
cd src/sherpa && make all && LD_LIBRARY_PATH=$HOME/.local/lib tclsh tests/test_recognize.tcl
```
Expected: `PASS` with a plausible transcript of `test_wavs/0.wav`.

- [ ] **Step 5: Commit**

```bash
git add src/sherpa/sherpa.tcl src/sherpa/tests/test_recognize.tcl
git commit -m "feat: sherpa-onnx streaming recognizer with endpoint signal"
```

---

### Task 4: Model-directory loader + registry entry

**Files:**
- Modify: `src/sherpa/sherpa.tcl` (add Tcl proc `sherpa::load_model` after `package provide`... actually before it, inside package)
- Modify: `src/engine.tcl:19-34` (registry: add `sherpa-onnx` entry + capability flags on all entries)
- Test: `src/sherpa/tests/test_load_model.tcl`

**Interfaces:**
- Consumes: `sherpa::create_recognizer` (Task 3).
- Produces: `sherpa::load_model -path <dir> -rate <hz>` → recognizer command (globs the standard `*.int8.onnx` files + `tokens.txt`). This is what `stt::create` (Task 5) calls for `sherpa-onnx`.

- [ ] **Step 1: Write the failing test** `src/sherpa/tests/test_load_model.tcl`

```tcl
lappend auto_path [file join [file dirname [info script]] .. lib]
package require sherpa
set model_dir [file normalize [file join [file dirname [info script]] \
    ../../../models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26]]
set rec [sherpa::load_model -path $model_dir -rate 16000]
if {[string match "sherpa_recognizer*" $rec] == 0} { puts "FAIL: no recognizer"; exit 1 }
$rec close
puts "PASS"
exit 0
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd src/sherpa && LD_LIBRARY_PATH=$HOME/.local/lib tclsh tests/test_load_model.tcl
```
Expected: FAIL — `invalid command name "sherpa::load_model"`.

- [ ] **Step 3: Add the loader proc** to `src/sherpa/sherpa.tcl`, immediately before `package provide sherpa 1.0`:

```tcl
# Resolve standard streaming-Zipformer file names from a model directory
proc sherpa::load_model {args} {
    array set opt {-rate 16000}
    array set opt $args
    set dir $opt(-path)
    set enc [lindex [glob -nocomplain -directory $dir encoder-*.int8.onnx] 0]
    set dec [lindex [glob -nocomplain -directory $dir decoder-*.int8.onnx] 0]
    set joi [lindex [glob -nocomplain -directory $dir joiner-*.int8.onnx] 0]
    set tok [file join $dir tokens.txt]
    foreach {name val} [list encoder $enc decoder $dec joiner $joi tokens $tok] {
        if {$val eq "" || ![file exists $val]} { error "sherpa::load_model: missing $name in $dir" }
    }
    return [sherpa::create_recognizer -encoder $enc -decoder $dec -joiner $joi -tokens $tok -rate $opt(-rate)]
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd src/sherpa && LD_LIBRARY_PATH=$HOME/.local/lib tclsh tests/test_load_model.tcl
```
Expected: `PASS`.

- [ ] **Step 5: Add registry entry + capability flags** in `src/engine.tcl`. Replace the `array set engine_registry { ... }` block (lines ~19-34) with:

```tcl
    array set engine_registry {
        vosk,command      ""
        vosk,type         "critcl"
        vosk,model_dir    "vosk"
        vosk,model_config "vosk_modelfile"
        vosk,endpointing  "external"
        vosk,emits_partials "yes"

        sherpa-onnx,command        ""
        sherpa-onnx,type           "critcl"
        sherpa-onnx,model_dir      "sherpa-onnx"
        sherpa-onnx,model_config   "sherpa_onnx_modelfile"
        sherpa-onnx,endpointing    "self"
        sherpa-onnx,emits_partials "yes"

        sherpa,command      "engines/sherpa_wrapper.sh"
        sherpa,type         "coprocess"
        sherpa,model_dir    "sherpa-onnx"
        sherpa,model_config "sherpa_modelfile"
        sherpa,endpointing  "external"
        sherpa,emits_partials "yes"

        faster-whisper,command      "engines/faster_whisper_wrapper.sh"
        faster-whisper,type         "coprocess"
        faster-whisper,model_dir    "faster-whisper"
        faster-whisper,model_config "faster_whisper_modelfile"
        faster-whisper,endpointing  "external"
        faster-whisper,emits_partials "no"
    }
```

- [ ] **Step 6: Verify engine.tcl still sources cleanly**

```bash
cd src && tclsh -c 'source engine.tcl; puts "engine.tcl OK"; puts [::engine::get_property sherpa-onnx endpointing]'
```
Expected: `engine.tcl OK` then `self`. (If `engine.tcl` requires Thread/other packages at source time and errors, instead run: `tclsh -c 'set f [open engine.tcl]; set s [read $f]; close $f; puts [expr {[string first "sherpa-onnx,endpointing" $s]>=0 ? "REGISTRY OK" : "MISSING"}]'`.)

- [ ] **Step 7: Commit**

```bash
git add src/sherpa/sherpa.tcl src/sherpa/tests/test_load_model.tcl src/engine.tcl
git commit -m "feat: sherpa-onnx model-dir loader + registry capability flags"
```

---

### Task 5: `stt::` dispatch layer + cross-engine contract test

**Files:**
- Create: `src/stt.tcl`
- Modify: `src/engine.tcl` (source `stt.tcl`; no call-site changes yet)
- Test: `src/stt_test.tcl`

**Interfaces:**
- Consumes: `sherpa::load_model`, `vosk::load_model`, `::coprocess::*`.
- Produces the single dispatch surface used by Task 6/7:
  - `stt::create $engine_name $type $model_path $rate` → handle
  - `stt::process $handle $type $chunk` → dict `{partial <str> endpoint 0|1}`
  - `stt::final $handle $type` → dict `{text <str>}`
  - `stt::reset $handle $type` → `ok`
  - `stt::destroy $handle $type` → `""`
  - Normalizes engine output: Vosk/coprocess return raw JSON (parsed via `json::json2dict`, `endpoint` defaulted to 0); sherpa-onnx returns a Tcl dict already.

- [ ] **Step 1: Write the failing contract test** `src/stt_test.tcl`

```tcl
lappend auto_path [file join [file dirname [info script]] sherpa lib]
lappend auto_path [file join [file dirname [info script]] vosk lib]
source [file join [file dirname [info script]] stt.tcl]

proc read_pcm {wav} { set f [open $wav rb]; set d [read $f]; close $f; return [string range $d 44 end] }

set root [file normalize [file join [file dirname [info script]] ..]]
set model_dir [file join $root models/sherpa-onnx/sherpa-onnx-streaming-zipformer-en-2023-06-26]
set pcm [read_pcm [file join $model_dir test_wavs 0.wav]]

# sherpa-onnx via stt:: (type=critcl, sherpa-onnx name)
set h [stt::create sherpa-onnx critcl $model_dir 16000]
set shape_ok 1
for {set i 0} {$i < [string length $pcm]} {incr i 3200} {
    set r [stt::process $h critcl [string range $pcm $i [expr {$i+3199}]]]
    if {![dict exists $r partial] || ![dict exists $r endpoint]} { set shape_ok 0 }
}
set fin [stt::final $h critcl]
stt::destroy $h critcl
if {!$shape_ok} { puts "FAIL: process shape"; exit 1 }
if {![dict exists $fin text] || [string length [string trim [dict get $fin text]]] < 3} { puts "FAIL: final text"; exit 1 }
puts "PASS: text='[dict get $fin text]'"
exit 0
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd src && LD_LIBRARY_PATH=$HOME/.local/lib tclsh stt_test.tcl
```
Expected: FAIL — `couldn't read file ".../stt.tcl"` or `invalid command "stt::create"`.

- [ ] **Step 3: Write `src/stt.tcl`**

```tcl
# stt.tcl - Common STT engine dispatch. One place branches critcl vs coprocess.
package require json

namespace eval stt {}

# Create a recognizer handle for an engine.
#   type: "critcl" | "coprocess"
proc stt::create {engine_name type model_path rate} {
    switch -- $type {
        critcl {
            switch -- $engine_name {
                vosk        { set m [vosk::load_model -path $model_path]; return [$m create_recognizer -rate $rate -alternatives 1] }
                sherpa-onnx { return [sherpa::load_model -path $model_path -rate $rate] }
                default     { error "stt::create: unknown critcl engine $engine_name" }
            }
        }
        coprocess {
            set cmd [::engine::get_property $engine_name command]
            return [::coprocess::start $engine_name $cmd $model_path $rate]
        }
        default { error "stt::create: unknown type $type" }
    }
}

# Normalize a critcl-or-coprocess process result to dict {partial <s> endpoint 0|1}
proc stt::_normalize_partial {raw} {
    if {[string match "*partial*" $raw] && [string match "*endpoint*" $raw] && [catch {dict size $raw}] == 0 && [dict exists $raw partial]} {
        # Already a Tcl dict (sherpa-onnx)
        return [list partial [dict get $raw partial] endpoint [expr {[dict exists $raw endpoint] ? [dict get $raw endpoint] : 0}]]
    }
    # Raw JSON (vosk / coprocess): {"partial":"..."} or {"text":"..."}
    set d [json::json2dict $raw]
    set partial [expr {[dict exists $d partial] ? [dict get $d partial] : ""}]
    set endpoint [expr {[dict exists $d endpoint] ? [dict get $d endpoint] : 0}]
    return [list partial $partial endpoint $endpoint]
}

proc stt::process {handle type chunk} {
    switch -- $type {
        critcl    { return [stt::_normalize_partial [$handle process $chunk]] }
        coprocess { return [stt::_normalize_partial [::coprocess::process $handle $chunk]] }
    }
}

proc stt::final {handle type} {
    switch -- $type {
        critcl    { set raw [$handle final-result] }
        coprocess { set raw [::coprocess::final $handle] }
    }
    if {[catch {dict get $raw text} txt] == 0 && [dict exists $raw text]} { return [list text $txt] }
    set d [json::json2dict $raw]
    return [list text [expr {[dict exists $d text] ? [dict get $d text] : ""}]]
}

proc stt::reset {handle type} {
    switch -- $type {
        critcl    { $handle reset }
        coprocess { ::coprocess::reset $handle }
    }
    return ok
}

proc stt::destroy {handle type} {
    switch -- $type {
        critcl    { catch {$handle close} }
        coprocess { ::coprocess::stop $handle }
    }
    return ""
}
```

Note on the sherpa-vs-JSON detection: sherpa-onnx `process` returns a **Tcl dict**; Vosk/coprocess return a **JSON string**. `stt::_normalize_partial` distinguishes them by attempting `dict exists $raw partial` on a well-formed dict. To make this robust, Task 3's dict is flat with keys `partial`/`endpoint`, and a Vosk JSON string like `{"partial":"foo"}` is NOT a valid 2-element Tcl dict, so `dict exists` on it fails and we fall through to JSON parsing. Verify this branch in Step 4.

- [ ] **Step 4: Add `source stt.tcl` to `engine.tcl`** near the top (after the existing `source .../coprocess.tcl` at line 9):

```tcl
source [file join [file dirname [info script]] stt.tcl]
```

- [ ] **Step 5: Run the contract test to verify it passes**

```bash
cd src && LD_LIBRARY_PATH=$HOME/.local/lib tclsh stt_test.tcl
```
Expected: `PASS: text='...'`.

- [ ] **Step 6: Commit**

```bash
git add src/stt.tcl src/stt_test.tcl src/engine.tcl
git commit -m "feat: stt:: dispatch layer + cross-engine contract test"
```

---

### Task 6: Capability-driven finalization (partial-stability for external engines)

**Files:**
- Modify: `src/engine.tcl` (`init` capability lookup; `process_chunk` returns dict; finalization branch)
- Test: `src/test_finalization.tcl`

**Interfaces:**
- Consumes: registry `endpointing` flag; `stt::process` dict output.
- Produces: `::engine::should_finalize` — a pure decision proc, unit-testable in isolation:
  - `::engine::should_finalize $self_endpoint $endpoint $partial_changed $silence_elapsed $silence_seconds $stable_elapsed $partial_stable_seconds` → `0|1`

- [ ] **Step 1: Write the failing unit test** `src/test_finalization.tcl`

```tcl
source [file join [file dirname [info script]] finalization.tcl]

# self-endpoint engine: finalize iff engine says endpoint
set ok 1
if {[::engine::should_finalize 1 1 0 0.0 0.15 0.0 0.6] != 1} { set ok 0 ;# endpoint fires }
if {[::engine::should_finalize 1 0 1 9.9 0.15 9.9 0.6] != 0} { set ok 0 ;# no endpoint => no finalize even if quiet }

# external engine: finalize on energy-silence OR partial-stability
if {[::engine::should_finalize 0 0 0 0.20 0.15 0.0 0.6] != 1} { set ok 0 ;# silence_elapsed>silence_seconds }
if {[::engine::should_finalize 0 0 0 0.05 0.15 0.70 0.6] != 1} { set ok 0 ;# stable_elapsed>partial_stable_seconds }
if {[::engine::should_finalize 0 0 0 0.05 0.15 0.10 0.6] != 0} { set ok 0 ;# neither => keep going }

puts [expr {$ok ? "PASS" : "FAIL"}]
exit [expr {$ok ? 0 : 1}]
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd src && tclsh test_finalization.tcl
```
Expected: FAIL — `couldn't read file ".../finalization.tcl"`.

- [ ] **Step 3: Create `src/finalization.tcl`** (extracted pure logic so it is testable without audio/threads)

```tcl
namespace eval engine {}

# Decide whether the current utterance should be finalized.
#   self_endpoint          : 1 if engine self-detects end-of-utterance
#   endpoint               : engine's endpoint flag this chunk (0|1)
#   partial_changed        : 1 if the partial text changed this chunk (unused for self)
#   silence_elapsed        : seconds since last speech (energy VAD)
#   silence_seconds        : configured energy-silence timeout
#   stable_elapsed         : seconds since the partial last changed
#   partial_stable_seconds : configured partial-stability timeout
proc engine::should_finalize {self_endpoint endpoint partial_changed \
        silence_elapsed silence_seconds stable_elapsed partial_stable_seconds} {
    if {$self_endpoint} {
        return [expr {$endpoint ? 1 : 0}]
    }
    if {$silence_elapsed > $silence_seconds} { return 1 }
    if {$stable_elapsed  > $partial_stable_seconds} { return 1 }
    return 0
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd src && tclsh test_finalization.tcl
```
Expected: `PASS`.

- [ ] **Step 5: Wire it into `engine.tcl`.** (a) `source finalization.tcl` near the other sources. (b) In `init`, add `variable self_endpoint [expr {[get_property $engine_name endpointing] eq "self"}]` and `variable last_partial_text ""` + `variable last_partial_change_ms 0` + read `config(partial_stable_seconds)` (default 0.6). (c) Change `process_chunk` (line ~424) to return the `stt::process` dict and, in the caller, track partial changes:

```tcl
                        } elseif {$last_speech_time} {
                            set pr [process_chunk $data]   ;# now returns dict {partial endpoint}
                            set partial [dict get $pr partial]
                            set endpoint [dict get $pr endpoint]
                            set nowms [clock milliseconds]
                            if {$partial ne $last_partial_text} {
                                set last_partial_text $partial
                                set last_partial_change_ms $nowms
                            }
                            set silence_elapsed [expr {$timestamp - $last_speech_time}]
                            set stable_elapsed [expr {($nowms - $last_partial_change_ms) / 1000.0}]
                            if {[engine::should_finalize $self_endpoint $endpoint 0 \
                                    $silence_elapsed $config(silence_seconds) \
                                    $stable_elapsed $config(partial_stable_seconds)]} {
                                process_final
                                set last_speech_time 0
                                set audio_buffer_list {}
                                set last_partial_text ""
                            } elseif {$speech} {
                                set last_speech_time $timestamp
                            }
                        }
```

And update `process_chunk` to `return [stt::process $recognizer $engine_type $chunk]` while still sending the partial to the UI (send `[dict get $result partial]`).

(Reference the existing block at `engine.tcl:395-417` — replace the `elseif {$last_speech_time}` branch with the above. Keep the `SEGMENT-SHORT` min-duration guard from the original inside the `process_final` path.)

- [ ] **Step 6: Verify the finalization unit test still passes and engine.tcl sources**

```bash
cd src && tclsh test_finalization.tcl && tclsh -c 'source finalization.tcl; puts OK'
```
Expected: `PASS` then `OK`.

- [ ] **Step 7: Commit**

```bash
git add src/finalization.tcl src/test_finalization.tcl src/engine.tcl
git commit -m "feat: capability-driven finalization (self-endpoint + partial-stability)"
```

---

### Task 7: Route remaining call sites through `stt::` + config default

**Files:**
- Modify: `src/engine.tcl` (replace the remaining inline `critcl`-vs-`coprocess` branches at `final`, `reset`, teardown with `stt::` calls; add `partial_stable_seconds` default)
- Modify: `src/audio.tcl` or the config defaults location (add `partial_stable_seconds 0.6`)

**Interfaces:**
- Consumes: `stt::final`, `stt::reset`, `stt::destroy`.
- Produces: no new interface; collapses the five-way branch to the single `stt::` layer.

- [ ] **Step 1: Replace `process_final`'s inline branch** (`engine.tcl:462-465`) with:

```tcl
                    set result [stt::final $recognizer $engine_type]
                    set text [dict get $result text]
```
(Downstream: send `$text` to the GEC/output path as the original did with the parsed `text` field.)

- [ ] **Step 2: Replace the `reset` inline branch** (`engine.tcl:530-533`) with:

```tcl
                    stt::reset $recognizer $engine_type
```

- [ ] **Step 3: Replace the teardown inline branch** (`engine.tcl:570-575`) with:

```tcl
                    stt::destroy $recognizer $engine_type
```

- [ ] **Step 4: Replace the critcl setup in `init`** (`engine.tcl:205-224`) so creation also goes through `stt::create`:

```tcl
                if {$engine_type eq "critcl" || $engine_type eq "coprocess"} {
                    set recognizer [stt::create $engine_name $engine_type $model_path $sample_rate]
                } else {
                    return [json::dict2json [list status error error "Unknown engine type: $engine_type"]]
                }
```
(Confirm `model_path` for `sherpa-onnx` resolves to the model directory via the existing `model_dir`/`model_config` lookup; `sherpa::load_model` globs the files inside it.)

- [ ] **Step 5: Add the config default** `partial_stable_seconds 0.6` wherever the `config` array defaults are initialized (search: `grep -rn "silence_seconds" src/*.tcl` and add the key beside it).

- [ ] **Step 6: Grep to confirm no stray inline engine-type branches remain in the hot path**

```bash
cd src && grep -n 'engine_type eq "critcl"' engine.tcl
```
Expected: only the single branch in `init` (Step 4) remains; `process`/`final`/`reset`/`destroy` no longer branch inline.

- [ ] **Step 7: Full binding + contract + finalization test sweep**

```bash
cd src/sherpa && make test && LD_LIBRARY_PATH=$HOME/.local/lib tclsh tests/test_recognize.tcl
cd ../ && LD_LIBRARY_PATH=$HOME/.local/lib tclsh stt_test.tcl && tclsh test_finalization.tcl
```
Expected: all `PASS`.

- [ ] **Step 8: Commit**

```bash
git add src/engine.tcl src/audio.tcl
git commit -m "refactor: route all engine ops through stt:: dispatch layer"
```

---

## Self-Review

**Spec coverage:**
- Common `stt::` contract (create/process/final/reset/destroy) → Task 5. ✓
- `endpoint` field in `process` → Task 3 (binding) + Task 5 (normalization). ✓
- Registry capability flags (`endpointing`, `emits_partials`) → Task 4. ✓
- sherpa-onnx streaming Zipformer critcl binding → Tasks 1-4. ✓
- Capability-driven finalization + partial-stability for external engines → Task 6. ✓
- Light dispatch cleanup (five branches → one) → Tasks 5 + 7. ✓
- Binding unit test + cross-engine contract test → Tasks 3, 5. ✓
- Coexist with Python `sherpa` coprocess (name `sherpa-onnx`) → Task 4 registry. ✓

**Out of scope (per spec):** whisper.cpp / OpenVINO bindings, WER bake-off, NPU. Not planned. ✓

**Type consistency:** `stt::process`→`{partial, endpoint}` (Task 5) matches binding output (Task 3) and finalization consumption (Task 6). `stt::final`→`{text}` matches `process_final` usage (Task 7). `engine::should_finalize` signature identical in Task 6 test, impl, and Task 6 Step 5 call site.

**Known risk to verify during execution:** exact sherpa-onnx config struct field names (Task 1 Step 5 gates Task 3). If the installed header differs, adapt Task 3's `config.*` assignments to the header's names before building.
