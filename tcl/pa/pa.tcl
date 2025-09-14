# pa.tcl - Critcl PortAudio Tcl package
# Save as pa.tcl and `package require pa` from Tcl (critcl will compile it)
package require critcl 3.1

# Ensure PortAudio headers & library available at compile time
critcl::cheaders /usr/include/portaudio.h
critcl::clibraries -lportaudio

# Namespace
namespace eval pa {}

########################
# C core: ring buffer, PortAudio callback, Tcl notify handler
critcl::ccode {
/* Headers */
#include <tcl.h>
#include <portaudio.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <time.h>

/* Simple single-producer single-consumer ring buffer (power-of-two capacity) */
typedef struct {
    unsigned char *buf;
    unsigned int size; /* power of two */
    unsigned int mask;
    volatile unsigned int head; /* write index (producer) */
    volatile unsigned int tail; /* read index (consumer) */
} SPSC_Ring;

static int rb_init(SPSC_Ring *rb, unsigned int capacity) {
    /* round up to power of two */
    unsigned int size = 1;
    while (size < capacity) size <<= 1;
    rb->buf = (unsigned char*)malloc(size);
    if (!rb->buf) return -1;
    rb->size = size;
    rb->mask = size - 1;
    rb->head = rb->tail = 0;
    return 0;
}
static void rb_free(SPSC_Ring *rb) {
    if (rb->buf) free(rb->buf);
    rb->buf = NULL;
}

/* Write up to n bytes; returns number actually written */
static unsigned int rb_write(SPSC_Ring *rb, const unsigned char *data, unsigned int n) {
    unsigned int head = rb->head;
    unsigned int tail = rb->tail;
    unsigned int free_space = rb->size - (head - tail);
    if (n > free_space) n = free_space;
    /* write in two parts if wrap-around */
    unsigned int idx = head & rb->mask;
    unsigned int first = rb->size - idx;
    if (first > n) first = n;
    memcpy(rb->buf + idx, data, first);
    if (n > first) memcpy(rb->buf, data + first, n - first);
    /* publish new head (single producer, relaxed) */
    rb->head = head + n;
    return n;
}

/* Read up to n bytes; returns number actually read */
static unsigned int rb_read(SPSC_Ring *rb, unsigned char *dst, unsigned int n) {
    unsigned int head = rb->head;
    unsigned int tail = rb->tail;
    unsigned int avail = head - tail;
    if (n > avail) n = avail;
    unsigned int idx = tail & rb->mask;
    unsigned int first = rb->size - idx;
    if (first > n) first = n;
    memcpy(dst, rb->buf + idx, first);
    if (n > first) memcpy(dst + first, rb->buf, n - first);
    rb->tail = tail + n;
    return n;
}

/* Peek available bytes */
static unsigned int rb_available(SPSC_Ring *rb) {
    return rb->head - rb->tail;
}

/* Stream context stored per stream object */
typedef struct {
    PaStream *stream;
    SPSC_Ring ring;
    int notify_fd[2];     /* socketpair: notify_fd[0]=reader (main), [1]=writer (audio) */
    Tcl_Interp *interp;
    Tcl_Obj *callback;    /* user callback script/command object (refcounted) */
    Tcl_Obj *cmdname;     /* name of the Tcl command representing this stream (refcounted) */
    int channels;
    double sampleRate;
    int framesPerBuffer;
    int sampleBytes;      /* bytes per sample (1? usually 2 or 4) */
    int fmt_tag;          /* 0=float32, 1=int16 */
    volatile unsigned int overflows;
    volatile unsigned int underruns;
    int closed;
    double start_time;    /* Pa_GetStreamTime at start; 0 if not started */
} StreamCtx;

/* Utility to get monotonic timestamp in seconds (double) */
static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* Audio thread callback - MINIMAL work: write frames into ring buffer and notify main thread */
static int pa_rt_callback(const void *inputBuffer, void *outputBuffer,
                          unsigned long framesPerBuffer,
                          const PaStreamCallbackTimeInfo* timeInfo,
                          PaStreamCallbackFlags statusFlags,
                          void *userData)
{
    (void) outputBuffer;
    (void) timeInfo;
    (void) statusFlags;

    StreamCtx *ctx = (StreamCtx*)userData;
    if (ctx->closed) return paComplete;

    unsigned int bytes = (unsigned int)(framesPerBuffer * ctx->channels * ctx->sampleBytes);
    const unsigned char *in = (const unsigned char*)inputBuffer;
    if (!in) {
        /* no input pointer: produce zeros */
        static const unsigned char z = 0;
        unsigned char *tmp = (unsigned char*)alloca(bytes);
        memset(tmp, 0, bytes);
        unsigned int wrote = rb_write(&ctx->ring, tmp, bytes);
        (void)wrote;
    } else {
        unsigned int wrote = rb_write(&ctx->ring, in, bytes);
        if (wrote < bytes) {
            ctx->overflows++;
            /* we drop the rest */
        }
    }

    /* notify main thread: write a single byte (non-blocking) */
    uint8_t one = 1;
    ssize_t r = write(ctx->notify_fd[1], &one, 1);
    (void)r;
    return paContinue;
}

/* Forward declaration for Tcl file handler */
static void tcl_notify_proc(ClientData cd, int mask);

/* Create non-blocking socketpair for notification */
static int create_notify_socketpair(int fds[2]) {
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == -1) return -1;
    /* set non-blocking on writer to avoid blocking in RT thread */
    int flags = fcntl(fds[1], F_GETFL, 0);
    if (flags != -1) fcntl(fds[1], F_SETFL, flags | O_NONBLOCK);
    /* also set non-blocking on reader for good measure */
    flags = fcntl(fds[0], F_GETFL, 0);
    if (flags != -1) fcntl(fds[0], F_SETFL, flags | O_NONBLOCK);
    return 0;
}

/* Tcl file handler - main thread: drain notify socket, drain ring buffer, and call user callback */
static void tcl_notify_proc(ClientData cd, int mask) {
    StreamCtx *ctx = (StreamCtx*)cd;
    Tcl_Interp *interp = ctx->interp;

    /* Drain the notify socket */
    uint8_t tmpbuf[64];
    while (1) {
        ssize_t rr = read(ctx->notify_fd[0], tmpbuf, sizeof(tmpbuf));
        if (rr <= 0) break;
    }

    /* Read up to a cap of available data to avoid extremely large Tcl objects */
    unsigned int avail = rb_available(&ctx->ring);
    if (avail == 0) return;

    /* Cap: deliver no more than 200 ms worth of data at once (configurable) */
    unsigned int bytes_per_sec = (unsigned int)(ctx->sampleRate * ctx->channels * ctx->sampleBytes);
    unsigned int cap = bytes_per_sec / 5; /* 200ms */
    if (cap < ctx->framesPerBuffer * ctx->channels * ctx->sampleBytes) {
        cap = ctx->framesPerBuffer * ctx->channels * ctx->sampleBytes;
    }
    if (avail > cap) avail = cap;

    unsigned char *buf = (unsigned char*)ckalloc(avail);
    unsigned int got = rb_read(&ctx->ring, buf, avail);

    /* Build Tcl command: callback + args: streamName timestamp data */
    if (ctx->callback && got > 0) {
        Tcl_IncrRefCount(ctx->callback); /* protect stored callback */
        /* Duplicate callback into a list command where first element is the callback string/command */
        Tcl_Obj *cmd = Tcl_DuplicateObj(ctx->callback);

        /* Append stream command name */
        Tcl_ListObjAppendElement(interp, cmd, ctx->cmdname);

        /* compute timestamp: time since start or monotonic now */
        double ts;
        if (ctx->start_time != 0.0) {
            ts = Pa_GetStreamTime(ctx->stream) - ctx->start_time;
        } else {
            ts = now_seconds();
        }
        Tcl_ListObjAppendElement(interp, cmd, Tcl_NewDoubleObj(ts));

        /* Append binary data object */
        Tcl_Obj *dataObj = Tcl_NewByteArrayObj(buf, got);
        Tcl_IncrRefCount(dataObj);
        Tcl_ListObjAppendElement(interp, cmd, dataObj);

        /* Evaluate */
        int code = Tcl_EvalObjEx(interp, cmd, TCL_EVAL_GLOBAL);
        if (code != TCL_OK) {
            const char *err = Tcl_GetStringResult(interp);
            Tcl_BackgroundError(interp); /* preserve error to background */
            /* continue; do not abort */
        }

        Tcl_DecrRefCount(dataObj);
        Tcl_DecrRefCount(cmd);
        Tcl_DecrRefCount(ctx->callback);
    }

    ckfree(buf);
}

/* Cleanup for stream object when command is deleted */
static void stream_delete(ClientData cd) {
    StreamCtx *ctx = (StreamCtx*)cd;
    if (!ctx) return;
    ctx->closed = 1;
    if (ctx->stream) {
        Pa_StopStream(ctx->stream);
        Pa_CloseStream(ctx->stream);
        ctx->stream = NULL;
    }
    /* remove Tcl file handler first */
    if (ctx->notify_fd[0] >= 0) {
        Tcl_DeleteFileHandler(ctx->notify_fd[0]);
    }
    if (ctx->notify_fd[0] >= 0) close(ctx->notify_fd[0]);
    if (ctx->notify_fd[1] >= 0) close(ctx->notify_fd[1]);
    rb_free(&ctx->ring);
    if (ctx->callback) Tcl_DecrRefCount(ctx->callback);
    if (ctx->cmdname) Tcl_DecrRefCount(ctx->cmdname);
    ckfree((char*)ctx);
}

/* Helper: find device index from name or "default" */
static int find_device_by_name(const char *name) {
    int count = Pa_GetDeviceCount();
    if (count < 0) return -1;
    if (!name || strcmp(name,"default")==0) {
        return Pa_GetDefaultInputDevice();
    }
    for (int i=0;i<count;i++) {
        const PaDeviceInfo *info = Pa_GetDeviceInfo(i);
        if (!info) continue;
        if (strstr(info->name, name)) return i;
    }
    return -1;
}

/* Tcl command: pa::init (optional) */
static int PaInitCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd; (void)objv; (void)objc;
    PaError err = Pa_Initialize();
    if (err != paNoError) {
        Tcl_AppendResult(interp, "Pa_Initialize failed: ", Pa_GetErrorText(err), NULL);
        return TCL_ERROR;
    }
    Tcl_SetObjResult(interp, Tcl_NewIntObj(0));
    return TCL_OK;
}

/* Tcl command: pa::list_devices -> list of dicts */
static int PaListDevicesCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd; (void)objc; (void)objv;
    int cnt = Pa_GetDeviceCount();
    if (cnt < 0) {
        Tcl_AppendResult(interp, "Pa_GetDeviceCount failed", NULL);
        return TCL_ERROR;
    }
    Tcl_Obj *res = Tcl_NewListObj(0, NULL);
    for (int i=0;i<cnt;i++) {
        const PaDeviceInfo *info = Pa_GetDeviceInfo(i);
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("index",-1), Tcl_NewIntObj(i));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("name",-1), Tcl_NewStringObj(info->name, -1));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("maxInputChannels",-1), Tcl_NewIntObj(info->maxInputChannels));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("defaultSampleRate",-1), Tcl_NewDoubleObj(info->defaultSampleRate));
        Tcl_ListObjAppendElement(interp, res, dict);
    }
    Tcl_SetObjResult(interp, res);
    return TCL_OK;
}

/* Stream object command dispatcher */
static int StreamObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    StreamCtx *ctx = (StreamCtx*)cd;
    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }
    const char *sub = Tcl_GetString(objv[1]);
    if (strcmp(sub,"start")==0) {
        if (!ctx->stream) {
            Tcl_AppendResult(interp,"stream not open",NULL);
            return TCL_ERROR;
        }
        PaError err = Pa_StartStream(ctx->stream);
        if (err != paNoError) {
            Tcl_AppendResult(interp, "Pa_StartStream: ", Pa_GetErrorText(err), NULL);
            return TCL_ERROR;
        }
        ctx->start_time = Pa_GetStreamTime(ctx->stream);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok",-1));
        return TCL_OK;
    } else if (strcmp(sub,"stop")==0) {
        if (!ctx->stream) return TCL_OK;
        PaError err = Pa_StopStream(ctx->stream);
        if (err != paNoError) {
            Tcl_AppendResult(interp, "Pa_StopStream: ", Pa_GetErrorText(err), NULL);
            return TCL_ERROR;
        }
        ctx->start_time = 0.0;
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok",-1));
        return TCL_OK;
    } else if (strcmp(sub,"info")==0) {
        Tcl_Obj *d = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, d, Tcl_NewStringObj("rate",-1), Tcl_NewDoubleObj(ctx->sampleRate));
        Tcl_DictObjPut(interp, d, Tcl_NewStringObj("channels",-1), Tcl_NewIntObj(ctx->channels));
        Tcl_DictObjPut(interp, d, Tcl_NewStringObj("framesPerBuffer",-1), Tcl_NewIntObj(ctx->framesPerBuffer));
        Tcl_DictObjPut(interp, d, Tcl_NewStringObj("overflows",-1), Tcl_NewIntObj((int)ctx->overflows));
        Tcl_DictObjPut(interp, d, Tcl_NewStringObj("underruns",-1), Tcl_NewIntObj((int)ctx->underruns));
        Tcl_SetObjResult(interp, d);
        return TCL_OK;
    } else if (strcmp(sub,"close")==0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok",-1));
        return TCL_OK;
    } else if (strcmp(sub,"setcallback")==0) {
        if (objc != 3) {
            Tcl_WrongNumArgs(interp, 2, objv, "setcallback script");
            return TCL_ERROR;
        }
        /* replace callback */
        if (ctx->callback) Tcl_DecrRefCount(ctx->callback);
        ctx->callback = objv[2];
        Tcl_IncrRefCount(ctx->callback);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok",-1));
        return TCL_OK;
    } else if (strcmp(sub,"stats")==0) {
        Tcl_Obj *d = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, d, Tcl_NewStringObj("overflows",-1), Tcl_NewIntObj((int)ctx->overflows));
        Tcl_DictObjPut(interp, d, Tcl_NewStringObj("underruns",-1), Tcl_NewIntObj((int)ctx->underruns));
        Tcl_SetObjResult(interp, d);
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub, "\"", NULL);
    return TCL_ERROR;
}

/* pa::open_stream - create StreamCtx, open PortAudio stream, create Tcl command */
static int PaOpenStreamCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    /* Default params */
    const char *device_arg = "default";
    double rate = 44100.0;
    int channels = 1;
    int framesPerBuffer = 256;
    const char *fmt = "float32";
    Tcl_Obj *callback = NULL;

    /* parse args (simple) */
    int i = 1;
    while (i < objc) {
        const char *opt = Tcl_GetString(objv[i]);
        if (strcmp(opt,"-device")==0 && i+1 < objc) { device_arg = Tcl_GetString(objv[++i]); }
        else if (strcmp(opt,"-rate")==0 && i+1 < objc) {
            if (Tcl_GetDoubleFromObj(interp, objv[++i], &rate) != TCL_OK) return TCL_ERROR;
        }
        else if (strcmp(opt,"-channels")==0 && i+1 < objc) {
            if (Tcl_GetIntFromObj(interp, objv[++i], &channels) != TCL_OK) return TCL_ERROR;
        }
        else if (strcmp(opt,"-frames")==0 && i+1 < objc) {
            if (Tcl_GetIntFromObj(interp, objv[++i], &framesPerBuffer) != TCL_OK) return TCL_ERROR;
        }
        else if (strcmp(opt,"-format")==0 && i+1 < objc) { fmt = Tcl_GetString(objv[++i]); }
        else if (strcmp(opt,"-callback")==0 && i+1 < objc) { callback = objv[++i]; }
        else {
            Tcl_AppendResult(interp, "unknown option ", opt, NULL);
            return TCL_ERROR;
        }
        i++;
    }

    /* find device */
    int dev = find_device_by_name(device_arg);
    if (dev < 0) {
        Tcl_AppendResult(interp, "device not found: ", device_arg, NULL);
        return TCL_ERROR;
    }
    const PaDeviceInfo *pinfo = Pa_GetDeviceInfo(dev);
    if (!pinfo) {
        Tcl_AppendResult(interp, "Pa_GetDeviceInfo failed", NULL);
        return TCL_ERROR;
    }

    /* create context */
    StreamCtx *ctx = (StreamCtx*)ckalloc(sizeof(StreamCtx));
    memset(ctx, 0, sizeof(*ctx));
    ctx->stream = NULL;
    ctx->interp = interp;
    ctx->callback = NULL;
    ctx->cmdname = NULL;
    ctx->channels = channels;
    ctx->sampleRate = rate;
    ctx->framesPerBuffer = framesPerBuffer;
    ctx->overflows = ctx->underruns = 0;
    ctx->start_time = 0.0;
    ctx->closed = 0;

    if (callback) {
        ctx->callback = callback;
        Tcl_IncrRefCount(ctx->callback);
    }

    if (strcmp(fmt,"float32")==0) {
        ctx->fmt_tag = 0;
        ctx->sampleBytes = 4;
    } else if (strcmp(fmt,"int16")==0) {
        ctx->fmt_tag = 1;
        ctx->sampleBytes = 2;
    } else {
        Tcl_AppendResult(interp, "unknown format: ", fmt, NULL);
        stream_delete((ClientData)ctx);
        return TCL_ERROR;
    }

    /* ring buffer: capacity = ~500ms of audio by default */
    unsigned int cap_bytes = (unsigned int)(ctx->sampleRate * ctx->channels * ctx->sampleBytes / 2); /* 500ms */
    if (cap_bytes < (unsigned int)(ctx->framesPerBuffer * ctx->channels * ctx->sampleBytes * 4))
        cap_bytes = ctx->framesPerBuffer * ctx->channels * ctx->sampleBytes * 4;
    if (rb_init(&ctx->ring, cap_bytes) != 0) {
        Tcl_AppendResult(interp, "ring buffer alloc failed", NULL);
        stream_delete((ClientData)ctx);
        return TCL_ERROR;
    }

    /* create notify socketpair */
    if (create_notify_socketpair(ctx->notify_fd) != 0) {
        Tcl_AppendResult(interp, "socketpair failed: ", strerror(errno), NULL);
        stream_delete((ClientData)ctx);
        return TCL_ERROR;
    }

    /* create PaStreamParameters */
    PaStreamParameters inputParams;
    memset(&inputParams, 0, sizeof(inputParams));
    inputParams.device = dev;
    inputParams.channelCount = ctx->channels;
    inputParams.sampleFormat = (ctx->fmt_tag == 0) ? paFloat32 : paInt16;
    inputParams.suggestedLatency = pinfo->defaultLowInputLatency;
    inputParams.hostApiSpecificStreamInfo = NULL;

    PaError err = Pa_OpenStream(&ctx->stream,
                               &inputParams,
                               NULL, /* no output */
                               ctx->sampleRate,
                               ctx->framesPerBuffer,
                               paNoFlag,
                               pa_rt_callback,
                               ctx);
    if (err != paNoError) {
        Tcl_AppendResult(interp, "Pa_OpenStream failed: ", Pa_GetErrorText(err), NULL);
        stream_delete((ClientData)ctx);
        return TCL_ERROR;
    }

    /* create unique Tcl command name */
    static int counter = 0;
    char namebuf[64];
    sprintf(namebuf, "pa%d", ++counter);
    Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, -1);
    Tcl_IncrRefCount(nameObj);
    ctx->cmdname = nameObj;

    /* register file handler in Tcl event loop */
    Tcl_CreateFileHandler(ctx->notify_fd[0], TCL_READABLE, tcl_notify_proc, (ClientData)ctx);

    /* create Tcl command object which dispatches subcommands */
    Tcl_CreateObjCommand(interp, namebuf, StreamObjCmd, (ClientData)ctx, stream_delete);

    /* return command name */
    Tcl_SetObjResult(interp, nameObj);
    return TCL_OK;
}

/* package initialization: create commands */
int Pa_InitPackage(Tcl_Interp *interp) {
    /* Ensure PortAudio initialized */
    Pa_Initialize();
    Tcl_CreateObjCommand(interp, "pa::init", PaInitCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "pa::list_devices", PaListDevicesCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "pa::open_stream", PaOpenStreamCmd, NULL, NULL);
    return TCL_OK;
}
} ;# end of ccode

# Wire up initialization
critcl::cproc Pa_Init {Tcl_Interp* interp} int {
    return Pa_InitPackage(interp);
}
# Export package commands
critcl::cproc pa::init {} int {
    PaError err = Pa_Initialize();
    if (err != paNoError) {
        return TCL_ERROR;
    }
    return TCL_OK;
}

# Provide the package
package provide pa 1.0

# Package commands are initialized by Pa_InitPackage in the C code
