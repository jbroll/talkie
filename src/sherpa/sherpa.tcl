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
        /* -rate is the INPUT audio rate; parse as double so "44100.0" works. */
        else if (strcmp(opt,"-rate")==0    && i+1<objc) { double r; if (Tcl_GetDoubleFromObj(interp,objv[++i],&r)!=TCL_OK) return TCL_ERROR; sample_rate=(int)r; }
        else { Tcl_AppendResult(interp,"unknown option ",opt,NULL); return TCL_ERROR; }
    }
    if (!encoder||!decoder||!joiner||!tokens) { Tcl_AppendResult(interp,"missing -encoder/-decoder/-joiner/-tokens",NULL); return TCL_ERROR; }

    SherpaOnnxOnlineRecognizerConfig config;
    memset(&config, 0, sizeof(config));
    /* Model expects 16 kHz features. AcceptWaveform is given the input rate
     * (ctx->sample_rate) and sherpa resamples input -> 16 kHz internally. */
    config.feat_config.sample_rate = 16000;
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

critcl::cinit {
    Tcl_CreateObjCommand(interp, "sherpa::create_recognizer", SherpaCreateRecognizerCmd, NULL, NULL);
} ""

# Runtime Tcl procs (bundled into the package; plain procs in this build
# script would otherwise run at build time only, not ship with the package).
critcl::tsources sherpa_procs.tcl

package provide sherpa 1.0
