#include "stt.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ========================================
 * STT Framework - Cleanup Functions
 * ======================================== */

void model_delete(ClientData cd) {
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

void recognizer_delete(ClientData cd) {
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

int RecognizerObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
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
        Tcl_SetObjResult(interp, Tcl_NewStringObj(result ? result : "", -1));
        return TCL_OK;
    }

    else if (strcmp(sub, "final-result") == 0) {
        const char *result = api->get_final(ctx);
        Tcl_SetObjResult(interp, Tcl_NewStringObj(result ? result : "", -1));
        return TCL_OK;
    }

    else if (strcmp(sub, "reset") == 0) {
        api->reset(ctx);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

/* ========================================
 * STT Framework - Unified Model API
 * ======================================== */

int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
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
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}