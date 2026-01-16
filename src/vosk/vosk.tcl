# vosk.tcl - Critcl Vosk speech recognition Tcl package
# Compatible with PortAudio binding for streaming audio processing
package require critcl 3.1

# Ensure Vosk headers & library available at compile time
critcl::cheaders $::env(HOME)/.local/include/vosk_api.h
critcl::clibraries -L$::env(HOME)/.local/lib -lvosk -lm -lstdc++
critcl::clibraries -L/usr/lib -ltclstub8.6

# Namespace
namespace eval vosk {}

########################
# C core: Vosk model and recognizer management
critcl::ccode {
#include <tcl.h>
#include <vosk_api.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* Model context for loaded Vosk models */
typedef struct {
    VoskModel *model;
    char *model_path;
    Tcl_Obj *cmdname;      /* name of the Tcl command representing this model */
} ModelCtx;

/* Recognizer context for individual recognizers */
typedef struct {
    VoskRecognizer *recognizer;
    ModelCtx *model_ctx;   /* reference to parent model */
    Tcl_Interp *interp;
    Tcl_Obj *cmdname;      /* name of the Tcl command representing this recognizer */
    float sample_rate;
    int beam;              /* beam search parameter */
    float confidence_threshold; /* confidence threshold for filtering */
    int max_alternatives;  /* max alternatives to return */
    int closed;
} RecognizerCtx;

/* Forward declarations */
static int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static int RecognizerObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static void model_delete(ClientData cd);
static void recognizer_delete(ClientData cd);

/* Utility functions */
static int GetIntParam(Tcl_Interp *interp, Tcl_Obj *obj, int *value) {
    Tcl_Size temp;
    int result = Tcl_GetSizeIntFromObj(interp, obj, &temp);
    if (result == TCL_OK) *value = (int)temp;
    return result;
}

static int GetDoubleParam(Tcl_Interp *interp, Tcl_Obj *obj, double *value) {
    return Tcl_GetDoubleFromObj(interp, obj, value);
}


/* Model cleanup when command is deleted */
static void model_delete(ClientData cd) {
    ModelCtx *ctx = (ModelCtx*)cd;
    if (!ctx) return;

    if (ctx->model) {
        vosk_model_free(ctx->model);
        ctx->model = NULL;
    }
    if (ctx->model_path) {
        ckfree(ctx->model_path);
        ctx->model_path = NULL;
    }
    if (ctx->cmdname) {
        Tcl_DecrRefCount(ctx->cmdname);
        ctx->cmdname = NULL;
    }
    ckfree((char*)ctx);
}

/* Recognizer cleanup when command is deleted */
static void recognizer_delete(ClientData cd) {
    RecognizerCtx *ctx = (RecognizerCtx*)cd;
    if (!ctx) return;

    ctx->closed = 1;
    if (ctx->recognizer) {
        vosk_recognizer_free(ctx->recognizer);
        ctx->recognizer = NULL;
    }
    if (ctx->cmdname) {
        Tcl_DecrRefCount(ctx->cmdname);
        ctx->cmdname = NULL;
    }
    /* Don't free model_ctx - it's owned by the model command */
    ckfree((char*)ctx);
}

/* Model object command dispatcher */
static int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    ModelCtx *ctx = (ModelCtx*)cd;
    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }

    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub, "info") == 0) {
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("path", TCL_AUTO_LENGTH),
                       Tcl_NewStringObj(ctx->model_path, TCL_AUTO_LENGTH));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("loaded", TCL_AUTO_LENGTH),
                       Tcl_NewBooleanObj(ctx->model != NULL));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "create_recognizer") == 0) {
        /* Parse options */
        float sample_rate = 16000.0;
        int beam = 10;
        float confidence_threshold = 0.0;
        int max_alternatives = 1;

        int i = 2;
        while (i < objc) {
            const char *opt = Tcl_GetString(objv[i]);
            if (strcmp(opt, "-rate") == 0 && i+1 < objc) {
                double rate;
                if (GetDoubleParam(interp, objv[++i], &rate) != TCL_OK) return TCL_ERROR;
                sample_rate = (float)rate;
            } else if (strcmp(opt, "-beam") == 0 && i+1 < objc) {
                if (GetIntParam(interp, objv[++i], &beam) != TCL_OK) return TCL_ERROR;
            } else if (strcmp(opt, "-confidence") == 0 && i+1 < objc) {
                double conf;
                if (GetDoubleParam(interp, objv[++i], &conf) != TCL_OK) return TCL_ERROR;
                confidence_threshold = (float)conf;
            } else if (strcmp(opt, "-alternatives") == 0 && i+1 < objc) {
                if (GetIntParam(interp, objv[++i], &max_alternatives) != TCL_OK) return TCL_ERROR;
            } else {
                Tcl_AppendResult(interp, "unknown option ", opt, NULL);
                return TCL_ERROR;
            }
            i++;
        }

        if (!ctx->model) {
            Tcl_AppendResult(interp, "model not loaded", NULL);
            return TCL_ERROR;
        }

        /* Create recognizer context */
        RecognizerCtx *rec_ctx = (RecognizerCtx*)ckalloc(sizeof(RecognizerCtx));
        memset(rec_ctx, 0, sizeof(*rec_ctx));

        rec_ctx->model_ctx = ctx;
        rec_ctx->interp = interp;
        rec_ctx->sample_rate = sample_rate;
        rec_ctx->beam = beam;
        rec_ctx->confidence_threshold = confidence_threshold;
        rec_ctx->max_alternatives = max_alternatives;
        rec_ctx->closed = 0;

        /* Create Vosk recognizer */
        rec_ctx->recognizer = vosk_recognizer_new(ctx->model, sample_rate);
        if (!rec_ctx->recognizer) {
            ckfree((char*)rec_ctx);
            Tcl_AppendResult(interp, "failed to create Vosk recognizer", NULL);
            return TCL_ERROR;
        }

        /* Callback functionality removed - processing inline now */

        /* Set recognizer parameters */
        vosk_recognizer_set_max_alternatives(rec_ctx->recognizer, max_alternatives);

        /* Create unique Tcl command name */
        static int recognizer_counter = 0;
        char namebuf[64];
        sprintf(namebuf, "vosk_recognizer%d", ++recognizer_counter);
        Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, TCL_AUTO_LENGTH);
        Tcl_IncrRefCount(nameObj);
        rec_ctx->cmdname = nameObj;

        /* Create Tcl command object */
        Tcl_CreateObjCommand(interp, namebuf, RecognizerObjCmd,
                             (ClientData)rec_ctx, recognizer_delete);

        /* Return command name */
        Tcl_SetObjResult(interp, nameObj);
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", TCL_AUTO_LENGTH));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

/* Recognizer object command dispatcher */
static int RecognizerObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    RecognizerCtx *ctx = (RecognizerCtx*)cd;

    /* Validate context pointer */
    if (!ctx) {
        Tcl_AppendResult(interp, "invalid recognizer context", NULL);
        return TCL_ERROR;
    }

    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }

    if (ctx->closed || !ctx->recognizer) {
        Tcl_AppendResult(interp, "recognizer closed", NULL);
        return TCL_ERROR;
    }

    /* Additional safety check */
    if (!ctx->interp || ctx->interp != interp) {
        Tcl_AppendResult(interp, "recognizer context corrupted", NULL);
        return TCL_ERROR;
    }

    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub, "process") == 0) {
        if (objc != 3) {
            Tcl_WrongNumArgs(interp, 2, objv, "audio_data");
            return TCL_ERROR;
        }

        /* Get binary audio data */
        Tcl_Size length;
        unsigned char *data = Tcl_GetByteArrayFromObj(objv[2], &length);

        /* Validate audio data */
        if (!data || length <= 0) {
            Tcl_AppendResult(interp, "invalid audio data", NULL);
            return TCL_ERROR;
        }

        /* Ensure reasonable buffer size (max 1MB) */
        if (length > 1024 * 1024) {
            Tcl_AppendResult(interp, "audio buffer too large", NULL);
            return TCL_ERROR;
        }

        /* Process with Vosk */
        int result = vosk_recognizer_accept_waveform(ctx->recognizer, (const char*)data, length);

        const char *json_result = NULL;

        if (result) {
            json_result = vosk_recognizer_final_result(ctx->recognizer);
        } else {
            json_result = vosk_recognizer_partial_result(ctx->recognizer);
        }

        Tcl_SetObjResult(interp, Tcl_NewStringObj(json_result ? json_result : "", TCL_AUTO_LENGTH));
        return TCL_OK;

    } else if (strcmp(sub, "final-result") == 0) {
        const char *json_result = vosk_recognizer_final_result(ctx->recognizer);
        Tcl_SetObjResult(interp, Tcl_NewStringObj(json_result ? json_result : "", TCL_AUTO_LENGTH));
        return TCL_OK;
    } else if (strcmp(sub, "reset") == 0) {
        vosk_recognizer_reset(ctx->recognizer);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", TCL_AUTO_LENGTH));
        return TCL_OK;

    } else if (strcmp(sub, "configure") == 0) {
        /* Parse configuration options */
        int i = 2;
        while (i < objc) {
            const char *opt = Tcl_GetString(objv[i]);
            if (strcmp(opt, "-beam") == 0 && i+1 < objc) {
                int beam;
                if (GetIntParam(interp, objv[++i], &beam) != TCL_OK) return TCL_ERROR;
                ctx->beam = beam;
                /* Note: Vosk C API doesn't expose beam setting directly */
            } else if (strcmp(opt, "-confidence") == 0 && i+1 < objc) {
                double conf;
                if (GetDoubleParam(interp, objv[++i], &conf) != TCL_OK) return TCL_ERROR;
                ctx->confidence_threshold = (float)conf;
            } else if (strcmp(opt, "-alternatives") == 0 && i+1 < objc) {
                int alts;
                if (GetIntParam(interp, objv[++i], &alts) != TCL_OK) return TCL_ERROR;
                ctx->max_alternatives = alts;
                vosk_recognizer_set_max_alternatives(ctx->recognizer, alts);
            } else {
                Tcl_AppendResult(interp, "unknown option ", opt, NULL);
                return TCL_ERROR;
            }
            i++;
        }
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", TCL_AUTO_LENGTH));
        return TCL_OK;

    } else if (strcmp(sub, "info") == 0) {
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("sample_rate", TCL_AUTO_LENGTH),
                       Tcl_NewDoubleObj(ctx->sample_rate));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("beam", TCL_AUTO_LENGTH),
                       Tcl_NewIntObj(ctx->beam));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("confidence_threshold", TCL_AUTO_LENGTH),
                       Tcl_NewDoubleObj(ctx->confidence_threshold));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("max_alternatives", TCL_AUTO_LENGTH),
                       Tcl_NewIntObj(ctx->max_alternatives));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", TCL_AUTO_LENGTH));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

/* Tcl command: vosk::load_model -path <path> */
static int VoskLoadModelCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;

    const char *model_path = NULL;

    /* Parse arguments */
    int i = 1;
    while (i < objc) {
        const char *opt = Tcl_GetString(objv[i]);
        if (strcmp(opt, "-path") == 0 && i+1 < objc) {
            model_path = Tcl_GetString(objv[++i]);
        } else {
            Tcl_AppendResult(interp, "unknown option ", opt, NULL);
            return TCL_ERROR;
        }
        i++;
    }

    if (!model_path) {
        Tcl_AppendResult(interp, "missing required option -path", NULL);
        return TCL_ERROR;
    }

    /* Create model context */
    ModelCtx *ctx = (ModelCtx*)ckalloc(sizeof(ModelCtx));
    memset(ctx, 0, sizeof(*ctx));

    /* Store model path */
    int path_len = strlen(model_path);
    ctx->model_path = (char*)ckalloc(path_len + 1);
    strcpy(ctx->model_path, model_path);

    /* Load Vosk model */
    ctx->model = vosk_model_new(model_path);

    if (!ctx->model) {
        ckfree(ctx->model_path);
        ckfree((char*)ctx);
        Tcl_AppendResult(interp, "failed to load Vosk model from: ", model_path, NULL);
        return TCL_ERROR;
    }

    /* Create unique Tcl command name */
    static int model_counter = 0;
    char namebuf[64];
    sprintf(namebuf, "vosk_model%d", ++model_counter);
    Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, TCL_AUTO_LENGTH);
    Tcl_IncrRefCount(nameObj);
    ctx->cmdname = nameObj;

    /* Create Tcl command object */
    Tcl_CreateObjCommand(interp, namebuf, ModelObjCmd, (ClientData)ctx, model_delete);

    /* Return command name */
    Tcl_SetObjResult(interp, nameObj);
    return TCL_OK;
}

} ;# end of ccode

critcl::cproc vosk::set_log_level {int level} int {
    vosk_set_log_level(level);
    return TCL_OK;
}

critcl::cinit {
    /* Initialize Vosk library safely - minimal initialization */
    vosk_set_log_level(-1);

    /* Create package commands */
    Tcl_CreateObjCommand(interp, "vosk::load_model", VoskLoadModelCmd, NULL, NULL);
} ""

package provide vosk 1.0
