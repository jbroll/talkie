package require critcl 3.1

# Include STT framework
critcl::csources stt.c
critcl::cheaders stt.h

# Include Sherpa-ONNX headers and libraries
critcl::cheaders ~/.local/include/sherpa-onnx-c-api.h
critcl::clibraries -L~/.local/lib -lsherpa-onnx-c-api -lsherpa-onnx-core -lsherpa-onnx-cxx-api -lsherpa-onnx-fst -lsherpa-onnx-fstfar -lsherpa-onnx-kaldifst-core -lssentencepiece_core -lkaldi-native-fbank-core -lkaldi-decoder-core -lonnxruntime -lcppinyin_core -lespeak-ng -lucd -lkissfft-float -lpiper_phonemize -lcargs -lm -lstdc++

critcl::cflags -fPIC

# Sherpa-ONNX Engine Implementation using STT Framework
critcl::ccode {
#include "stt.h"
#include "sherpa-onnx-c-api.h"
#include <string.h>
#include <stdio.h>

/* For Sherpa-ONNX:
 * RecognizerCtx->recognizer = SherpaOnnxOnlineStream
 * RecognizerCtx->model = SherpaOnnxOnlineRecognizer
 */

static void sherpa_model_free_impl(void *model) {
    SherpaOnnxDestroyOnlineRecognizer((SherpaOnnxOnlineRecognizer*)model);
}

static void sherpa_recognizer_free_impl(void *recognizer) {
    /* recognizer is actually SherpaOnnxOnlineStream */
    SherpaOnnxDestroyOnlineStream((SherpaOnnxOnlineStream*)recognizer);
}

static int sherpa_accept_waveform_impl(void *recognizer, const char *data, int length) {
    /* recognizer is actually SherpaOnnxOnlineStream */
    SherpaOnnxOnlineStream *stream = (SherpaOnnxOnlineStream*)recognizer;

    /* Convert byte data to float samples (assuming 16-bit PCM) */
    int num_samples = length / 2;
    float *samples = (float*)malloc(num_samples * sizeof(float));

    short *input = (short*)data;
    for (int i = 0; i < num_samples; i++) {
        samples[i] = (float)input[i] / 32768.0f;
    }

    SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, samples, num_samples);
    free(samples);

    return 1; /* Always return 1 for successful processing */
}

static const char* sherpa_get_text_impl(struct RecognizerCtx *ctx) {
    /* For online processing, return partial results */
    SherpaOnnxOnlineRecognizer *recognizer = (SherpaOnnxOnlineRecognizer*)ctx->model;
    SherpaOnnxOnlineStream *stream = (SherpaOnnxOnlineStream*)ctx->recognizer;

    const char *json_result = SherpaOnnxGetOnlineStreamResultAsJson(recognizer, stream);
    return json_result ? json_result : "{\"partial\": \"\"}";
}

static const char* sherpa_get_final_impl(struct RecognizerCtx *ctx) {
    /* For online processing, also return JSON result */
    SherpaOnnxOnlineRecognizer *recognizer = (SherpaOnnxOnlineRecognizer*)ctx->model;
    SherpaOnnxOnlineStream *stream = (SherpaOnnxOnlineStream*)ctx->recognizer;

    const char *json_result = SherpaOnnxGetOnlineStreamResultAsJson(recognizer, stream);
    return json_result ? json_result : "{\"text\": \"\"}";
}

static void sherpa_reset_impl(struct RecognizerCtx *ctx) {
    /* Reset online stream state */
    SherpaOnnxOnlineRecognizer *recognizer = (SherpaOnnxOnlineRecognizer*)ctx->model;
    SherpaOnnxOnlineStream *stream = (SherpaOnnxOnlineStream*)ctx->recognizer;

    SherpaOnnxOnlineStreamReset(recognizer, stream);
}

/* Forward declaration for recognizer creation */
static int sherpa_create_recognizer(ModelCtx *model_ctx, Tcl_Interp *interp, int sample_rate);

/* Sherpa-ONNX engine API table */
static EngineAPI sherpa_engine_api = {
    sherpa_model_free_impl,
    sherpa_recognizer_free_impl,
    sherpa_accept_waveform_impl,
    sherpa_get_text_impl,
    sherpa_get_final_impl,
    sherpa_reset_impl,
    sherpa_create_recognizer
};

/* Sherpa-ONNX-specific recognizer creation that uses the STT framework */
static int sherpa_create_recognizer(ModelCtx *model_ctx, Tcl_Interp *interp, int sample_rate) {
    /* Get the Sherpa-ONNX online recognizer */
    SherpaOnnxOnlineRecognizer *recognizer = (SherpaOnnxOnlineRecognizer*)model_ctx->model;

    /* Create Sherpa-ONNX online stream */
    SherpaOnnxOnlineStream *stream = SherpaOnnxCreateOnlineStream(recognizer);
    if (!stream) {
        Tcl_AppendResult(interp, "failed to create Sherpa-ONNX online stream", NULL);
        return TCL_ERROR;
    }

    /* Create recognizer context */
    RecognizerCtx *rec_ctx = (RecognizerCtx*)ckalloc(sizeof(RecognizerCtx));
    rec_ctx->recognizer = stream;          /* Stream for accept_waveform */
    rec_ctx->model = recognizer;           /* Recognizer for get_text/get_final */
    rec_ctx->model_ctx = model_ctx;
    rec_ctx->interp = interp;
    rec_ctx->sample_rate = (float)sample_rate;
    rec_ctx->closed = 0;

    static int sherpa_recognizer_counter = 0;
    char cmd_name[64];
    snprintf(cmd_name, sizeof(cmd_name), "sherpa_recognizer%d", ++sherpa_recognizer_counter);

    rec_ctx->cmdname = Tcl_NewStringObj(cmd_name, -1);
    Tcl_IncrRefCount(rec_ctx->cmdname);

    Tcl_CreateObjCommand(interp, cmd_name, RecognizerObjCmd, rec_ctx, recognizer_delete);
    Tcl_SetObjResult(interp, rec_ctx->cmdname);
    return TCL_OK;
}

/* Sherpa-ONNX model creation command */
int SherpaCreateModelCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 3 || strcmp(Tcl_GetString(objv[1]), "-path") != 0) {
        Tcl_WrongNumArgs(interp, 1, objv, "-path <modelpath>");
        return TCL_ERROR;
    }
    const char *path = Tcl_GetString(objv[2]);

    /* Configure Sherpa-ONNX online recognizer for streaming transducer model */
    SherpaOnnxOnlineRecognizerConfig config;
    memset(&config, 0, sizeof(config));

    /* Build paths for transducer model files */
    char encoder_path[1024];
    char decoder_path[1024];
    char joiner_path[1024];
    char tokens_path[1024];

    snprintf(encoder_path, sizeof(encoder_path), "%s/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", path);
    snprintf(decoder_path, sizeof(decoder_path), "%s/decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", path);
    snprintf(joiner_path, sizeof(joiner_path), "%s/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx", path);
    snprintf(tokens_path, sizeof(tokens_path), "%s/tokens.txt", path);

    /* Configure feature extraction */
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;

    /* Configure online transducer model */
    config.model_config.transducer.encoder = encoder_path;
    config.model_config.transducer.decoder = decoder_path;
    config.model_config.transducer.joiner = joiner_path;
    config.model_config.tokens = tokens_path;
    config.model_config.num_threads = 1;
    config.model_config.debug = 0;
    config.model_config.provider = "cpu";

    /* Configure decoding parameters */
    config.decoding_method = "greedy_search";
    config.max_active_paths = 4;
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = 2.4;
    config.rule2_min_trailing_silence = 1.2;
    config.rule3_min_utterance_length = 20.0;

    SherpaOnnxOnlineRecognizer *model = SherpaOnnxCreateOnlineRecognizer(&config);
    if (!model) {
        Tcl_AppendResult(interp, "failed to load Sherpa-ONNX model from ", path, NULL);
        return TCL_ERROR;
    }

    ModelCtx *ctx = (ModelCtx*)ckalloc(sizeof(ModelCtx));
    ctx->model = model;
    ctx->model_path = (char*)ckalloc(strlen(path) + 1);
    strcpy(ctx->model_path, path);
    ctx->engine_type = (char*)ckalloc(12);
    strcpy(ctx->engine_type, "sherpa-onnx");
    ctx->engine_funcs = &sherpa_engine_api;

    static int sherpa_model_counter = 0;
    char cmd_name[64];
    snprintf(cmd_name, sizeof(cmd_name), "sherpa_model%d", ++sherpa_model_counter);

    ctx->cmdname = Tcl_NewStringObj(cmd_name, -1);
    Tcl_IncrRefCount(ctx->cmdname);

    Tcl_CreateObjCommand(interp, cmd_name, ModelObjCmd, ctx, model_delete);
    Tcl_SetObjResult(interp, ctx->cmdname);
    return TCL_OK;
}

} ;# end critcl ccode

critcl::ccommand create_sherpa_model {cd interp objc objv} {
    return SherpaCreateModelCmd(cd, interp, objc, objv);
}

# Initialize Sherpa-ONNX (minimal setup)
critcl::cinit {
    /* No specific initialization needed for Sherpa-ONNX */
} ""

package provide sherpa_onnx 1.0
