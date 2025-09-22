package require critcl 3.1

# Include STT framework
critcl::csources stt.c
critcl::cheaders stt.h

# Include Vosk headers and libraries
critcl::cheaders ~/.local/include/vosk_api.h
critcl::clibraries -L~/.local/lib -lvosk -lm -lstdc++

critcl::cflags -fPIC

# Vosk Engine Implementation using STT Framework
critcl::ccode {
#include "stt.h"
#include "vosk_api.h"
#include <string.h>
#include <stdio.h>

static void vosk_model_free_impl(void *model) {
    vosk_model_free((VoskModel*)model);
}

static void vosk_recognizer_free_impl(void *recognizer) {
    vosk_recognizer_free((VoskRecognizer*)recognizer);
}

static int vosk_accept_waveform_impl(void *recognizer, const char *data, int length) {
    return vosk_recognizer_accept_waveform((VoskRecognizer*)recognizer, data, length);
}

static const char* vosk_get_text_impl(struct RecognizerCtx *ctx) {
    return vosk_recognizer_partial_result((VoskRecognizer*)ctx->recognizer);
}

static const char* vosk_get_final_impl(struct RecognizerCtx *ctx) {
    return vosk_recognizer_final_result((VoskRecognizer*)ctx->recognizer);
}

static void vosk_reset_impl(struct RecognizerCtx *ctx) {
    vosk_recognizer_reset((VoskRecognizer*)ctx->recognizer);
}

/* Forward declaration for recognizer creation */
static int vosk_create_recognizer(ModelCtx *model_ctx, Tcl_Interp *interp, int sample_rate);

/* Vosk engine API table */
static EngineAPI vosk_engine_api = {
    vosk_model_free_impl,
    vosk_recognizer_free_impl,
    vosk_accept_waveform_impl,
    vosk_get_text_impl,
    vosk_get_final_impl,
    vosk_reset_impl,
    vosk_create_recognizer
};

/* Vosk-specific recognizer creation that uses the STT framework */
static int vosk_create_recognizer(ModelCtx *model_ctx, Tcl_Interp *interp, int sample_rate) {
    /* Create Vosk recognizer */
    VoskRecognizer *recognizer = vosk_recognizer_new((VoskModel*)model_ctx->model, (float)sample_rate);
    if (!recognizer) {
        Tcl_AppendResult(interp, "failed to create Vosk recognizer", NULL);
        return TCL_ERROR;
    }

    /* Create recognizer context */
    RecognizerCtx *rec_ctx = (RecognizerCtx*)ckalloc(sizeof(RecognizerCtx));
    rec_ctx->recognizer = recognizer;
    rec_ctx->model = model_ctx->model;  /* Vosk doesn't need this but set for consistency */
    rec_ctx->model_ctx = model_ctx;
    rec_ctx->interp = interp;
    rec_ctx->sample_rate = (float)sample_rate;
    rec_ctx->closed = 0;

    static int vosk_recognizer_counter = 0;
    char cmd_name[64];
    snprintf(cmd_name, sizeof(cmd_name), "vosk_recognizer%d", ++vosk_recognizer_counter);

    rec_ctx->cmdname = Tcl_NewStringObj(cmd_name, -1);
    Tcl_IncrRefCount(rec_ctx->cmdname);

    Tcl_CreateObjCommand(interp, cmd_name, RecognizerObjCmd, rec_ctx, recognizer_delete);
    Tcl_SetObjResult(interp, rec_ctx->cmdname);
    return TCL_OK;
}

/* Vosk model creation command */
int VoskCreateModelCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 3 || strcmp(Tcl_GetString(objv[1]), "-path") != 0) {
        Tcl_WrongNumArgs(interp, 1, objv, "-path <modelpath>");
        return TCL_ERROR;
    }
    const char *path = Tcl_GetString(objv[2]);

    VoskModel *model = vosk_model_new(path);
    if (!model) {
        Tcl_AppendResult(interp, "failed to load Vosk model from ", path, NULL);
        return TCL_ERROR;
    }

    ModelCtx *ctx = (ModelCtx*)ckalloc(sizeof(ModelCtx));
    ctx->model = model;
    ctx->model_path = (char*)ckalloc(strlen(path) + 1);
    strcpy(ctx->model_path, path);
    ctx->engine_type = (char*)ckalloc(5);
    strcpy(ctx->engine_type, "vosk");
    ctx->engine_funcs = &vosk_engine_api;

    static int vosk_model_counter = 0;
    char cmd_name[64];
    snprintf(cmd_name, sizeof(cmd_name), "vosk_model%d", ++vosk_model_counter);

    ctx->cmdname = Tcl_NewStringObj(cmd_name, -1);
    Tcl_IncrRefCount(ctx->cmdname);

    Tcl_CreateObjCommand(interp, cmd_name, ModelObjCmd, ctx, model_delete);
    Tcl_SetObjResult(interp, ctx->cmdname);
    return TCL_OK;
}

} ;# end critcl ccode

critcl::ccommand create_vosk_model {cd interp objc objv} {
    return VoskCreateModelCmd(cd, interp, objc, objv);
}

# Initialize Vosk
critcl::cinit {
    vosk_set_log_level(-1); /* Suppress Vosk logging */
} ""

package provide vosk 1.0
