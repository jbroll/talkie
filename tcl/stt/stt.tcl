package require critcl 3.1

# Include engine headers and libraries
critcl::cheaders ~/.local/include/vosk_api.h
critcl::cheaders ~/.local/include/sherpa-onnx-c-api.h
critcl::clibraries -L~/.local/lib -lvosk -lsherpa-onnx-c-api -lsherpa-onnx-core -lsherpa-onnx-cxx-api -lsherpa-onnx-fst -lsherpa-onnx-fstfar -lsherpa-onnx-kaldifst-core -lssentencepiece_core -lkaldi-native-fbank-core -lkaldi-decoder-core -lonnxruntime -lcppinyin_core -lespeak-ng -lucd -lkissfft-float -lpiper_phonemize -lcargs -lm -lstdc++

critcl::cflags -fPIC

# STT Framework - Core unified API
critcl::ccode {
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ========================================
 * STT Framework - Unified Structures
 * ======================================== */

/* Generic model context for any STT engine */
typedef struct ModelCtx {
    void *model;           /* Engine-specific model pointer */
    char *model_path;
    char *engine_type;     /* "vosk", "sherpa", etc */
    Tcl_Obj *cmdname;
    void *engine_funcs;    /* Engine function table */
} ModelCtx;

/* Generic recognizer context for any STT engine */
typedef struct RecognizerCtx {
    void *recognizer;      /* Engine-specific recognizer pointer (e.g., stream) */
    void *model;           /* Engine-specific model pointer for engines that need it */
    ModelCtx *model_ctx;
    Tcl_Interp *interp;
    Tcl_Obj *cmdname;
    float sample_rate;
    int closed;
} RecognizerCtx;

/* Forward declaration */
struct RecognizerCtx;

/* Engine function table interface */
typedef struct EngineAPI {
    void (*model_free)(void *model);
    void (*recognizer_free)(void *recognizer);
    int (*accept_waveform)(void *recognizer, const char *data, int length);
    const char* (*get_text)(struct RecognizerCtx *ctx);
    const char* (*get_final)(struct RecognizerCtx *ctx);
    void (*reset)(struct RecognizerCtx *ctx);
    int (*create_recognizer)(ModelCtx *model_ctx, Tcl_Interp *interp, int sample_rate);
} EngineAPI;

/* Forward declarations */
static int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static int RecognizerObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static void model_delete(ClientData cd);
static void recognizer_delete(ClientData cd);


/* No engine-specific declarations needed - engines use this framework */

/* ========================================
 * STT Framework - Cleanup Functions
 * ======================================== */

static void model_delete(ClientData cd) {
    ModelCtx *ctx = (ModelCtx*)cd;
    if (!ctx) return;

    if (ctx->model && ctx->engine_funcs) {
        EngineAPI *api = (EngineAPI*)ctx->engine_funcs;
        api->model_free(ctx->model);
        ctx->model = NULL;
    }

    if (ctx->model_path) {
        ckfree(ctx->model_path);
        ctx->model_path = NULL;
    }
    if (ctx->engine_type) {
        ckfree(ctx->engine_type);
        ctx->engine_type = NULL;
    }
    if (ctx->cmdname) {
        Tcl_DecrRefCount(ctx->cmdname);
        ctx->cmdname = NULL;
    }
    ckfree((char*)ctx);
}

static void recognizer_delete(ClientData cd) {
    RecognizerCtx *ctx = (RecognizerCtx*)cd;
    if (!ctx) return;
    ctx->closed = 1;

    if (ctx->recognizer && ctx->model_ctx && ctx->model_ctx->engine_funcs) {
        EngineAPI *api = (EngineAPI*)ctx->model_ctx->engine_funcs;
        api->recognizer_free(ctx->recognizer);
        ctx->recognizer = NULL;
    }

    /* Clear model pointer (this is just a reference, don't free it) */
    ctx->model = NULL;

    if (ctx->cmdname) {
        Tcl_DecrRefCount(ctx->cmdname);
        ctx->cmdname = NULL;
    }
    ckfree((char*)ctx);
}

/* ========================================
 * STT Framework - Unified Recognizer API
 * ======================================== */

static int RecognizerObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    RecognizerCtx *ctx = (RecognizerCtx*)cd;
    if (!ctx || ctx->closed) {
        Tcl_AppendResult(interp, "recognizer closed", NULL);
        return TCL_ERROR;
    }
    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }

    const char *sub = Tcl_GetString(objv[1]);
    EngineAPI *api = (EngineAPI*)ctx->model_ctx->engine_funcs;

    if (strcmp(sub, "accept-waveform") == 0) {
        if (objc != 3) {
            Tcl_WrongNumArgs(interp, 2, objv, "audio_data");
            return TCL_ERROR;
        }

        int length;
        unsigned char *data = Tcl_GetByteArrayFromObj(objv[2], &length);
        if (!data || length <= 0) {
            Tcl_AppendResult(interp, "invalid audio data", NULL);
            return TCL_ERROR;
        }

        int result = api->accept_waveform(ctx->recognizer, (const char*)data, length);
        Tcl_SetObjResult(interp, Tcl_NewBooleanObj(result));
        return TCL_OK;
    }

    else if (strcmp(sub, "text") == 0) {
        const char *result = api->get_text(ctx);
        Tcl_SetObjResult(interp, Tcl_NewStringObj(result ? result : "", TCL_AUTO_LENGTH));
        return TCL_OK;
    }

    else if (strcmp(sub, "final-result") == 0) {
        const char *result = api->get_final(ctx);
        Tcl_SetObjResult(interp, Tcl_NewStringObj(result ? result : "", TCL_AUTO_LENGTH));
        return TCL_OK;
    }

    else if (strcmp(sub, "reset") == 0) {
        api->reset(ctx);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", TCL_AUTO_LENGTH));
        return TCL_OK;
    }

    else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", TCL_AUTO_LENGTH));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

/* ========================================
 * STT Framework - Unified Model API
 * ======================================== */

static int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    ModelCtx *ctx = (ModelCtx*)cd;
    if (!ctx) {
        Tcl_AppendResult(interp, "model deleted", NULL);
        return TCL_ERROR;
    }

    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }

    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub, "create_recognizer") == 0) {
        if (objc != 4 || strcmp(Tcl_GetString(objv[2]), "-rate") != 0) {
            Tcl_WrongNumArgs(interp, 2, objv, "-rate sample_rate");
            return TCL_ERROR;
        }

        int sample_rate;
        if (Tcl_GetIntFromObj(interp, objv[3], &sample_rate) != TCL_OK) {
            return TCL_ERROR;
        }

        /* Use engine API for recognizer creation */
        EngineAPI *api = (EngineAPI*)ctx->engine_funcs;
        if (api && api->create_recognizer) {
            return api->create_recognizer(ctx, interp, sample_rate);
        } else {
            Tcl_AppendResult(interp, "create_recognizer not implemented for engine: ",
                            ctx->engine_type ? ctx->engine_type : "unknown", NULL);
            return TCL_ERROR;
        }
    }

    else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", TCL_AUTO_LENGTH));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

} ;# end critcl ccode


namespace eval stt {
    source [file join [file dirname [info script]] vosk.tcl]
    source [file join [file dirname [info script]] sherpa-onnx.tcl]
}
package provide stt 1.0
