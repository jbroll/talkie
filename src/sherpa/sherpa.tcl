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
    const char *provider="cpu";
    /* Model-intrinsic constants for this streaming Zipformer (16kHz, 80-dim
     * fbank); the rest are tuning knobs, overridable via options / config. */
    int model_rate = 16000, feature_dim = 80;
    int sample_rate = 16000;      /* INPUT audio rate (device rate) */
    int num_threads = 2, max_active_paths = 4;
    double rule1 = 2.4, rule2 = 1.2, rule3 = 20.0;
    for (int i = 1; i < objc; i++) {
        const char *opt = Tcl_GetString(objv[i]);
        double d;  /* checked scratch for numeric options */
        if      (strcmp(opt,"-encoder")==0 && i+1<objc) encoder = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-decoder")==0 && i+1<objc) decoder = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-joiner")==0  && i+1<objc) joiner  = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-tokens")==0  && i+1<objc) tokens  = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-provider")==0 && i+1<objc) provider = Tcl_GetString(objv[++i]);
        /* Numerics parsed as double (so "44100.0"/"4.0" from JSON config work). */
        else if (strcmp(opt,"-rate")==0        && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; sample_rate=(int)d; }
        else if (strcmp(opt,"-model-rate")==0  && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; model_rate=(int)d; }
        else if (strcmp(opt,"-feature-dim")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; feature_dim=(int)d; }
        else if (strcmp(opt,"-num-threads")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; num_threads=(int)d; }
        else if (strcmp(opt,"-max-active-paths")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; max_active_paths=(int)d; }
        else if (strcmp(opt,"-rule1")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&rule1)!=TCL_OK) return TCL_ERROR; }
        else if (strcmp(opt,"-rule2")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&rule2)!=TCL_OK) return TCL_ERROR; }
        else if (strcmp(opt,"-rule3")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&rule3)!=TCL_OK) return TCL_ERROR; }
        else { Tcl_AppendResult(interp,"unknown option ",opt,NULL); return TCL_ERROR; }
    }
    if (!encoder||!decoder||!joiner||!tokens) { Tcl_AppendResult(interp,"missing -encoder/-decoder/-joiner/-tokens",NULL); return TCL_ERROR; }

    SherpaOnnxOnlineRecognizerConfig config;
    memset(&config, 0, sizeof(config));
    /* AcceptWaveform gets the input rate (ctx->sample_rate); sherpa resamples
     * input -> model_rate internally. */
    config.feat_config.sample_rate = model_rate;
    config.feat_config.feature_dim = feature_dim;
    config.model_config.transducer.encoder = encoder;
    config.model_config.transducer.decoder = decoder;
    config.model_config.transducer.joiner  = joiner;
    config.model_config.tokens = tokens;
    config.model_config.num_threads = num_threads;
    config.model_config.provider = provider;
    config.model_config.debug = 0;
    config.decoding_method = "greedy_search";
    config.max_active_paths = max_active_paths;
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = (float)rule1;
    config.rule2_min_trailing_silence = (float)rule2;
    config.rule3_min_utterance_length = (float)rule3;

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

/* ---- Offline (non-streaming) recognizer: Parakeet, Whisper, etc. --------
 * Batch engine: `process` buffers the utterance's audio and emits no partial
 * or endpoint; `final-result` runs one decode over the whole buffer. Endpoint
 * detection is the app's job (VAD / partial-stability). */
typedef struct {
    const SherpaOnnxOfflineRecognizer *recognizer;
    Tcl_Interp *interp;
    Tcl_Obj *cmdname;
    int sample_rate;
    float *buf; int buf_len; int buf_cap;  /* accumulated waveform */
    int closed;
} SherpaOfflineCtx;

static void sherpa_offline_delete(ClientData cd) {
    SherpaOfflineCtx *ctx = (SherpaOfflineCtx*)cd;
    if (!ctx) return;
    ctx->closed = 1;
    if (ctx->recognizer) { SherpaOnnxDestroyOfflineRecognizer(ctx->recognizer); ctx->recognizer = NULL; }
    if (ctx->buf)        { ckfree((char*)ctx->buf); ctx->buf = NULL; }
    if (ctx->cmdname)    { Tcl_DecrRefCount(ctx->cmdname); ctx->cmdname = NULL; }
    ckfree((char*)ctx);
}

static int SherpaOfflineObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    SherpaOfflineCtx *ctx = (SherpaOfflineCtx*)cd;
    if (!ctx || ctx->closed) { Tcl_AppendResult(interp,"recognizer closed",NULL); return TCL_ERROR; }
    if (objc < 2) { Tcl_WrongNumArgs(interp,1,objv,"subcommand ?args?"); return TCL_ERROR; }
    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub,"process")==0) {
        if (objc != 3) { Tcl_WrongNumArgs(interp,2,objv,"audio_data"); return TCL_ERROR; }
        Tcl_Size length;
        unsigned char *data = Tcl_GetByteArrayFromObj(objv[2], &length);
        int n = (int)(length / 2);
        if (data && n > 0) {
            if (ctx->buf_len + n > ctx->buf_cap) {
                int newcap = (ctx->buf_len + n) * 2;
                ctx->buf = (float*)ckrealloc((char*)ctx->buf, newcap * sizeof(float));
                ctx->buf_cap = newcap;
            }
            const short *pcm = (const short*)data;
            for (int i = 0; i < n; i++) ctx->buf[ctx->buf_len + i] = pcm[i] / 32768.0f;
            ctx->buf_len += n;
        }
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("partial",-1), Tcl_NewStringObj("",-1));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("endpoint",-1), Tcl_NewIntObj(0));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub,"final-result")==0) {
        static char textbuf[16384]; textbuf[0]='\0';
        if (ctx->buf_len > 0) {
            const SherpaOnnxOfflineStream *stream = SherpaOnnxCreateOfflineStream(ctx->recognizer);
            SherpaOnnxAcceptWaveformOffline(stream, ctx->sample_rate, ctx->buf, ctx->buf_len);
            SherpaOnnxDecodeOfflineStream(ctx->recognizer, stream);
            const SherpaOnnxOfflineRecognizerResult *res = SherpaOnnxGetOfflineStreamResult(stream);
            if (res && res->text) { strncpy(textbuf, res->text, sizeof(textbuf)-1); textbuf[sizeof(textbuf)-1]='\0'; }
            if (res) SherpaOnnxDestroyOfflineRecognizerResult(res);
            SherpaOnnxDestroyOfflineStream(stream);
        }
        ctx->buf_len = 0;
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("text",-1), Tcl_NewStringObj(textbuf,-1));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub,"reset")==0) {
        ctx->buf_len = 0;
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok",-1));
        return TCL_OK;
    } else if (strcmp(sub,"close")==0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok",-1));
        return TCL_OK;
    }
    Tcl_AppendResult(interp,"unknown subcommand \"",sub,"\"",NULL);
    return TCL_ERROR;
}

static int SherpaCreateOfflineRecognizerCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    const char *encoder=NULL,*decoder=NULL,*joiner=NULL,*tokens=NULL;
    const char *provider="cpu",*model_type="",*decoding_method="greedy_search";
    int sample_rate = 16000, num_threads = 2, max_active_paths = 4;
    for (int i = 1; i < objc; i++) {
        const char *opt = Tcl_GetString(objv[i]);
        double d;
        if      (strcmp(opt,"-encoder")==0 && i+1<objc) encoder = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-decoder")==0 && i+1<objc) decoder = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-joiner")==0  && i+1<objc) joiner  = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-tokens")==0  && i+1<objc) tokens  = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-provider")==0 && i+1<objc) provider = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-model-type")==0 && i+1<objc) model_type = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-decoding-method")==0 && i+1<objc) decoding_method = Tcl_GetString(objv[++i]);
        else if (strcmp(opt,"-rate")==0        && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; sample_rate=(int)d; }
        else if (strcmp(opt,"-num-threads")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; num_threads=(int)d; }
        else if (strcmp(opt,"-max-active-paths")==0 && i+1<objc) { if (Tcl_GetDoubleFromObj(interp,objv[++i],&d)!=TCL_OK) return TCL_ERROR; max_active_paths=(int)d; }
        else { Tcl_AppendResult(interp,"unknown option ",opt,NULL); return TCL_ERROR; }
    }
    if (!encoder||!decoder||!joiner||!tokens) { Tcl_AppendResult(interp,"missing -encoder/-decoder/-joiner/-tokens",NULL); return TCL_ERROR; }

    SherpaOnnxOfflineRecognizerConfig config;
    memset(&config, 0, sizeof(config));
    config.model_config.transducer.encoder = encoder;
    config.model_config.transducer.decoder = decoder;
    config.model_config.transducer.joiner  = joiner;
    config.model_config.tokens = tokens;
    config.model_config.num_threads = num_threads;
    config.model_config.provider = provider;
    config.model_config.debug = 0;
    config.model_config.model_type = model_type;
    config.decoding_method = decoding_method;
    config.max_active_paths = max_active_paths;

    const SherpaOnnxOfflineRecognizer *recognizer = SherpaOnnxCreateOfflineRecognizer(&config);
    if (!recognizer) { Tcl_AppendResult(interp,"failed to create sherpa-onnx offline recognizer",NULL); return TCL_ERROR; }

    SherpaOfflineCtx *ctx = (SherpaOfflineCtx*)ckalloc(sizeof(SherpaOfflineCtx));
    memset(ctx,0,sizeof(*ctx));
    ctx->recognizer = recognizer; ctx->interp = interp; ctx->sample_rate = sample_rate; ctx->closed = 0;

    static int ocounter = 0;
    char namebuf[64];
    sprintf(namebuf,"sherpa_offline%d",++ocounter);
    Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf,-1);
    Tcl_IncrRefCount(nameObj);
    ctx->cmdname = nameObj;
    Tcl_CreateObjCommand(interp, namebuf, SherpaOfflineObjCmd, (ClientData)ctx, sherpa_offline_delete);
    Tcl_SetObjResult(interp, nameObj);
    return TCL_OK;
}

}

critcl::cinit {
    Tcl_CreateObjCommand(interp, "sherpa::create_recognizer", SherpaCreateRecognizerCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "sherpa::create_offline_recognizer", SherpaCreateOfflineRecognizerCmd, NULL, NULL);
} ""

# Runtime Tcl procs (bundled into the package; plain procs in this build
# script would otherwise run at build time only, not ship with the package).
critcl::tsources sherpa_procs.tcl

package provide sherpa 1.0
