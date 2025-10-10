# sherpa-onnx.tcl - Critcl Sherpa-ONNX speech recognition Tcl package
# Follows the same pattern as vosk/vosk.tcl
package require critcl 3.1

# Ensure Sherpa-ONNX headers & libraries available at compile time
critcl::cflags -I/home/john/.local/include
critcl::clibraries -L/home/john/.local/lib -lsherpa-onnx-c-api -lsherpa-onnx-core -lsherpa-onnx-cxx-api -lsherpa-onnx-fst -lsherpa-onnx-fstfar -lsherpa-onnx-kaldifst-core -lssentencepiece_core -lkaldi-native-fbank-core -lkaldi-decoder-core -lonnxruntime -lcppinyin_core -lespeak-ng -lucd -lkissfft-float -lpiper_phonemize -lcargs -lm -lstdc++

# Namespace
namespace eval sherpa {}

########################
# C core: Sherpa-ONNX model and recognizer management
critcl::ccode {
#include <tcl.h>
#include <sherpa-onnx/c-api/c-api.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* Model context for loaded Sherpa-ONNX models */
typedef struct {
    SherpaOnnxOnlineRecognizer *recognizer;  /* Sherpa's "model" is the recognizer object */
    char *model_path;
    Tcl_Obj *cmdname;
} ModelCtx;

/* Stream context for individual recognition streams */
typedef struct {
    SherpaOnnxOnlineStream *stream;
    ModelCtx *model_ctx;
    Tcl_Interp *interp;
    Tcl_Obj *cmdname;
    float sample_rate;
    int max_active_paths;
    float confidence_threshold;
    int closed;
} StreamCtx;

/* Forward declarations */
static int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static int StreamObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static void model_delete(ClientData cd);
static void stream_delete(ClientData cd);

/* Utility functions */
static int GetIntParam(Tcl_Interp *interp, Tcl_Obj *obj, int *value) {
    return Tcl_GetIntFromObj(interp, obj, value);
}

static int GetDoubleParam(Tcl_Interp *interp, Tcl_Obj *obj, double *value) {
    return Tcl_GetDoubleFromObj(interp, obj, value);
}

/* Model cleanup when command is deleted */
static void model_delete(ClientData cd) {
    ModelCtx *ctx = (ModelCtx*)cd;
    if (!ctx) return;

    if (ctx->recognizer) {
        SherpaOnnxDestroyOnlineRecognizer(ctx->recognizer);
        ctx->recognizer = NULL;
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

/* Stream cleanup when command is deleted */
static void stream_delete(ClientData cd) {
    StreamCtx *ctx = (StreamCtx*)cd;
    if (!ctx) return;

    ctx->closed = 1;
    if (ctx->stream) {
        SherpaOnnxDestroyOnlineStream(ctx->stream);
        ctx->stream = NULL;
    }
    if (ctx->cmdname) {
        Tcl_DecrRefCount(ctx->cmdname);
        ctx->cmdname = NULL;
    }
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
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("path", -1),
                       Tcl_NewStringObj(ctx->model_path, -1));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("loaded", -1),
                       Tcl_NewBooleanObj(ctx->recognizer != NULL));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "create_recognizer") == 0) {
        /* Parse options */
        float sample_rate = 16000.0;
        int max_active_paths = 4;
        float confidence_threshold = 0.0;

        int i = 2;
        while (i < objc) {
            const char *opt = Tcl_GetString(objv[i]);
            if (strcmp(opt, "-rate") == 0 && i+1 < objc) {
                double rate;
                if (GetDoubleParam(interp, objv[++i], &rate) != TCL_OK) return TCL_ERROR;
                sample_rate = (float)rate;
            } else if (strcmp(opt, "-max_active_paths") == 0 && i+1 < objc) {
                if (GetIntParam(interp, objv[++i], &max_active_paths) != TCL_OK) return TCL_ERROR;
            } else if (strcmp(opt, "-confidence") == 0 && i+1 < objc) {
                double conf;
                if (GetDoubleParam(interp, objv[++i], &conf) != TCL_OK) return TCL_ERROR;
                confidence_threshold = (float)conf;
            } else {
                Tcl_AppendResult(interp, "unknown option ", opt, NULL);
                return TCL_ERROR;
            }
            i++;
        }

        if (!ctx->recognizer) {
            Tcl_AppendResult(interp, "model not loaded", NULL);
            return TCL_ERROR;
        }

        /* Create stream context */
        StreamCtx *stream_ctx = (StreamCtx*)ckalloc(sizeof(StreamCtx));
        memset(stream_ctx, 0, sizeof(*stream_ctx));

        stream_ctx->model_ctx = ctx;
        stream_ctx->interp = interp;
        stream_ctx->sample_rate = sample_rate;
        stream_ctx->max_active_paths = max_active_paths;
        stream_ctx->confidence_threshold = confidence_threshold;
        stream_ctx->closed = 0;

        /* Create Sherpa-ONNX stream */
        stream_ctx->stream = SherpaOnnxCreateOnlineStream(ctx->recognizer);
        if (!stream_ctx->stream) {
            ckfree((char*)stream_ctx);
            Tcl_AppendResult(interp, "failed to create Sherpa-ONNX stream", NULL);
            return TCL_ERROR;
        }

        /* Create unique Tcl command name */
        static int stream_counter = 0;
        char namebuf[64];
        sprintf(namebuf, "sherpa_stream%d", ++stream_counter);
        Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, -1);
        Tcl_IncrRefCount(nameObj);
        stream_ctx->cmdname = nameObj;

        /* Create Tcl command object */
        Tcl_CreateObjCommand(interp, namebuf, StreamObjCmd,
                             (ClientData)stream_ctx, stream_delete);

        /* Return command name */
        Tcl_SetObjResult(interp, nameObj);
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

/* Stream object command dispatcher */
static int StreamObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    StreamCtx *ctx = (StreamCtx*)cd;

    /* Validate context pointer */
    if (!ctx) {
        Tcl_AppendResult(interp, "invalid stream context", NULL);
        return TCL_ERROR;
    }

    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }

    if (ctx->closed || !ctx->stream) {
        Tcl_AppendResult(interp, "stream closed", NULL);
        return TCL_ERROR;
    }

    /* Additional safety check */
    if (!ctx->interp || ctx->interp != interp) {
        Tcl_AppendResult(interp, "stream context corrupted", NULL);
        return TCL_ERROR;
    }

    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub, "process") == 0) {
        if (objc != 3) {
            Tcl_WrongNumArgs(interp, 2, objv, "audio_data");
            return TCL_ERROR;
        }

        /* Get binary audio data */
        int length;
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

        /* Convert 16-bit PCM to float samples */
        int num_samples = length / 2;
        float *samples = (float*)ckalloc(num_samples * sizeof(float));
        short *input = (short*)data;
        for (int i = 0; i < num_samples; i++) {
            samples[i] = (float)input[i] / 32768.0f;
        }

        /* Process with Sherpa-ONNX */
        SherpaOnnxOnlineStreamAcceptWaveform(ctx->stream, (int)ctx->sample_rate, samples, num_samples);
        ckfree((char*)samples);

        /* Check if result is ready */
        int is_ready = SherpaOnnxIsOnlineStreamReady(ctx->model_ctx->recognizer, ctx->stream);

        if (is_ready) {
            SherpaOnnxDecodeOnlineStream(ctx->model_ctx->recognizer, ctx->stream);
        }

        /* Get result as JSON */
        const char *json_result = SherpaOnnxGetOnlineStreamResultAsJson(ctx->model_ctx->recognizer, ctx->stream);

        Tcl_SetObjResult(interp, Tcl_NewStringObj(json_result ? json_result : "{}", -1));
        SherpaOnnxDestroyOnlineStreamResultJson(json_result);
        return TCL_OK;

    } else if (strcmp(sub, "final-result") == 0) {
        /* Signal input finished to flush all phonemes */
        SherpaOnnxOnlineStreamInputFinished(ctx->stream);

        /* Decode any remaining audio */
        while (SherpaOnnxIsOnlineStreamReady(ctx->model_ctx->recognizer, ctx->stream)) {
            SherpaOnnxDecodeOnlineStream(ctx->model_ctx->recognizer, ctx->stream);
        }

        /* Get final result */
        const char *json_result = SherpaOnnxGetOnlineStreamResultAsJson(ctx->model_ctx->recognizer, ctx->stream);

        /* Save result before resetting */
        Tcl_Obj *result = Tcl_NewStringObj(json_result ? json_result : "{}", -1);
        SherpaOnnxDestroyOnlineStreamResultJson(json_result);

        /* Reset stream immediately to clear finished state and accept new audio */
        SherpaOnnxOnlineStreamReset(ctx->model_ctx->recognizer, ctx->stream);

        Tcl_SetObjResult(interp, result);
        return TCL_OK;

    } else if (strcmp(sub, "reset") == 0) {
        SherpaOnnxOnlineStreamReset(ctx->model_ctx->recognizer, ctx->stream);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;

    } else if (strcmp(sub, "configure") == 0) {
        /* Parse configuration options */
        int i = 2;
        while (i < objc) {
            const char *opt = Tcl_GetString(objv[i]);
            if (strcmp(opt, "-max_active_paths") == 0 && i+1 < objc) {
                int paths;
                if (GetIntParam(interp, objv[++i], &paths) != TCL_OK) return TCL_ERROR;
                ctx->max_active_paths = paths;
            } else if (strcmp(opt, "-confidence") == 0 && i+1 < objc) {
                double conf;
                if (GetDoubleParam(interp, objv[++i], &conf) != TCL_OK) return TCL_ERROR;
                ctx->confidence_threshold = (float)conf;
            } else {
                Tcl_AppendResult(interp, "unknown option ", opt, NULL);
                return TCL_ERROR;
            }
            i++;
        }
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;

    } else if (strcmp(sub, "info") == 0) {
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("sample_rate", -1),
                       Tcl_NewDoubleObj(ctx->sample_rate));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("max_active_paths", -1),
                       Tcl_NewIntObj(ctx->max_active_paths));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("confidence_threshold", -1),
                       Tcl_NewDoubleObj(ctx->confidence_threshold));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

/* Tcl command: sherpa::load_model -path <path> ?options? */
static int SherpaLoadModelCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;

    const char *model_path = NULL;
    const char *provider = "cpu";
    int num_threads = 1;
    int debug = 0;

    /* Parse arguments */
    int i = 1;
    while (i < objc) {
        const char *opt = Tcl_GetString(objv[i]);
        if (strcmp(opt, "-path") == 0 && i+1 < objc) {
            model_path = Tcl_GetString(objv[++i]);
        } else if (strcmp(opt, "-provider") == 0 && i+1 < objc) {
            provider = Tcl_GetString(objv[++i]);
        } else if (strcmp(opt, "-threads") == 0 && i+1 < objc) {
            if (GetIntParam(interp, objv[++i], &num_threads) != TCL_OK) return TCL_ERROR;
        } else if (strcmp(opt, "-debug") == 0 && i+1 < objc) {
            if (GetIntParam(interp, objv[++i], &debug) != TCL_OK) return TCL_ERROR;
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

    /* Configure Sherpa-ONNX */
    SherpaOnnxOnlineRecognizerConfig config;
    memset(&config, 0, sizeof(config));

    /* Build paths for transducer model files */
    char encoder_path[1024];
    char decoder_path[1024];
    char joiner_path[1024];
    char tokens_path[1024];

    snprintf(encoder_path, sizeof(encoder_path), "%s/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", model_path);
    snprintf(decoder_path, sizeof(decoder_path), "%s/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", model_path);
    snprintf(joiner_path, sizeof(joiner_path), "%s/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx", model_path);
    snprintf(tokens_path, sizeof(tokens_path), "%s/tokens.txt", model_path);

    /* Configure feature extraction */
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;

    /* Configure online transducer model */
    config.model_config.transducer.encoder = encoder_path;
    config.model_config.transducer.decoder = decoder_path;
    config.model_config.transducer.joiner = joiner_path;
    config.model_config.tokens = tokens_path;
    config.model_config.num_threads = num_threads;
    config.model_config.debug = debug;
    config.model_config.provider = provider;

    /* Configure decoding parameters */
    config.decoding_method = "greedy_search";
    config.max_active_paths = 4;
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = 2.4;
    config.rule2_min_trailing_silence = 1.2;
    config.rule3_min_utterance_length = 20.0;

    /* Load Sherpa-ONNX model */
    ctx->recognizer = SherpaOnnxCreateOnlineRecognizer(&config);

    if (!ctx->recognizer) {
        ckfree(ctx->model_path);
        ckfree((char*)ctx);
        Tcl_AppendResult(interp, "failed to load Sherpa-ONNX model from: ", model_path, NULL);
        return TCL_ERROR;
    }

    /* Create unique Tcl command name */
    static int model_counter = 0;
    char namebuf[64];
    sprintf(namebuf, "sherpa_model%d", ++model_counter);
    Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, -1);
    Tcl_IncrRefCount(nameObj);
    ctx->cmdname = nameObj;

    /* Create Tcl command object */
    Tcl_CreateObjCommand(interp, namebuf, ModelObjCmd, (ClientData)ctx, model_delete);

    /* Return command name */
    Tcl_SetObjResult(interp, nameObj);
    return TCL_OK;
}

} ;# end of ccode

critcl::cinit {
    /* Initialize Sherpa-ONNX library */
    /* No specific initialization needed */

    /* Create package commands */
    Tcl_CreateObjCommand(interp, "sherpa::load_model", SherpaLoadModelCmd, NULL, NULL);
} ""

package provide sherpa 1.0
