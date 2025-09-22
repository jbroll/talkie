#ifndef STT_H
#define STT_H

#include <tcl.h>

/* ========================================
 * STT Framework - Unified Structures
 * ======================================== */

/* Forward declarations */
struct RecognizerCtx;
struct ModelCtx;

/* Engine function table interface */
typedef struct EngineAPI {
    void (*model_free)(void *model);
    void (*recognizer_free)(void *recognizer);
    int (*accept_waveform)(void *recognizer, const char *data, int length);
    const char* (*get_text)(struct RecognizerCtx *ctx);
    const char* (*get_final)(struct RecognizerCtx *ctx);
    void (*reset)(struct RecognizerCtx *ctx);
    int (*create_recognizer)(struct ModelCtx *model_ctx, Tcl_Interp *interp, int sample_rate);
} EngineAPI;

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

/* ========================================
 * STT Framework - Function Declarations
 * ======================================== */

/* Command handlers */
int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
int RecognizerObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);

/* Cleanup functions */
void model_delete(ClientData cd);
void recognizer_delete(ClientData cd);

#endif /* STT_H */