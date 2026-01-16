# gec.tcl - Critcl OpenVINO bindings for Grammar Error Correction
# Provides inference on Intel NPU using OpenVINO C API
package require critcl 3.1

# OpenVINO paths
set ov_include /home/john/pkg/openvino-src/src/bindings/c/include
set ov_lib /home/john/pkg/openvino-src/bin/intel64/Release

# Configure critcl for OpenVINO
critcl::cheaders -I$ov_include
critcl::clibraries -L$ov_lib -lopenvino_c -lopenvino

# Link against Tcl stubs library (required for Tcl 9)
critcl::clibraries -L/usr/lib -ltclstub8.6

# Namespace
namespace eval gec {}

########################
# C core: OpenVINO model management
critcl::ccode {
#include <tcl.h>
#include <openvino/c/openvino.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* Global OpenVINO core - shared across all models */
static ov_core_t* g_core = NULL;
static int g_core_refcount = 0;

/* Model context for loaded OpenVINO models */
typedef struct {
    ov_model_t *model;                    /* Original model */
    ov_compiled_model_t *compiled_model;  /* Compiled for specific device */
    char *model_path;
    char *device_name;
    Tcl_Obj *cmdname;                     /* Name of the Tcl command */
    Tcl_Interp *interp;
} ModelCtx;

/* Infer request context */
typedef struct {
    ov_infer_request_t *request;
    ModelCtx *model_ctx;                  /* Reference to parent model */
    Tcl_Obj *cmdname;
    Tcl_Interp *interp;
    int closed;
} InferCtx;

/* Forward declarations */
static int ModelObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static int InferObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static void model_delete(ClientData cd);
static void infer_delete(ClientData cd);

/* Utility: convert ov_status_e to string */
static const char* ov_status_to_string(ov_status_e status) {
    switch(status) {
        case OK: return "OK";
        case GENERAL_ERROR: return "GENERAL_ERROR";
        case NOT_IMPLEMENTED: return "NOT_IMPLEMENTED";
        case NETWORK_NOT_LOADED: return "NETWORK_NOT_LOADED";
        case PARAMETER_MISMATCH: return "PARAMETER_MISMATCH";
        case NOT_FOUND: return "NOT_FOUND";
        case OUT_OF_BOUNDS: return "OUT_OF_BOUNDS";
        case UNEXPECTED: return "UNEXPECTED";
        case REQUEST_BUSY: return "REQUEST_BUSY";
        case RESULT_NOT_READY: return "RESULT_NOT_READY";
        case NOT_ALLOCATED: return "NOT_ALLOCATED";
        case INFER_NOT_STARTED: return "INFER_NOT_STARTED";
        case NETWORK_NOT_READ: return "NETWORK_NOT_READ";
        case INFER_CANCELLED: return "INFER_CANCELLED";
        case INVALID_C_PARAM: return "INVALID_C_PARAM";
        case UNKNOWN_C_ERROR: return "UNKNOWN_C_ERROR";
        case NOT_IMPLEMENT_C_METHOD: return "NOT_IMPLEMENT_C_METHOD";
        case UNKNOW_EXCEPTION: return "UNKNOW_EXCEPTION";
        default: return "UNKNOWN";
    }
}

/* Utility: set Tcl error with OpenVINO status */
static int SetOVError(Tcl_Interp *interp, const char *msg, ov_status_e status) {
    const char *err_msg = ov_get_last_err_msg();
    char buf[4096];
    snprintf(buf, sizeof(buf), "%s: %s (%d)%s%s",
             msg, ov_status_to_string(status), status,
             err_msg ? " - " : "", err_msg ? err_msg : "");
    Tcl_SetObjResult(interp, Tcl_NewStringObj(buf, -1));
    return TCL_ERROR;
}

/* Initialize OpenVINO core (reference counted) */
static int init_core(Tcl_Interp *interp) {
    if (g_core != NULL) {
        g_core_refcount++;
        return TCL_OK;
    }

    ov_status_e status = ov_core_create(&g_core);
    if (status != OK) {
        return SetOVError(interp, "Failed to create OpenVINO core", status);
    }
    g_core_refcount = 1;
    return TCL_OK;
}

/* Release OpenVINO core reference */
static void release_core(void) {
    if (g_core_refcount > 0) {
        g_core_refcount--;
        if (g_core_refcount == 0 && g_core != NULL) {
            ov_core_free(g_core);
            g_core = NULL;
        }
    }
}

/* Model cleanup when command is deleted */
static void model_delete(ClientData cd) {
    ModelCtx *ctx = (ModelCtx*)cd;
    if (!ctx) return;

    if (ctx->compiled_model) {
        ov_compiled_model_free(ctx->compiled_model);
        ctx->compiled_model = NULL;
    }
    if (ctx->model) {
        ov_model_free(ctx->model);
        ctx->model = NULL;
    }
    if (ctx->model_path) {
        ckfree(ctx->model_path);
        ctx->model_path = NULL;
    }
    if (ctx->device_name) {
        ckfree(ctx->device_name);
        ctx->device_name = NULL;
    }
    if (ctx->cmdname) {
        Tcl_DecrRefCount(ctx->cmdname);
        ctx->cmdname = NULL;
    }
    release_core();
    ckfree((char*)ctx);
}

/* Infer request cleanup */
static void infer_delete(ClientData cd) {
    InferCtx *ctx = (InferCtx*)cd;
    if (!ctx) return;

    ctx->closed = 1;
    if (ctx->request) {
        ov_infer_request_free(ctx->request);
        ctx->request = NULL;
    }
    if (ctx->cmdname) {
        Tcl_DecrRefCount(ctx->cmdname);
        ctx->cmdname = NULL;
    }
    /* Don't free model_ctx - owned by model command */
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
        /* Return model information */
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("path", -1),
                       Tcl_NewStringObj(ctx->model_path, -1));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("device", -1),
                       Tcl_NewStringObj(ctx->device_name, -1));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("compiled", -1),
                       Tcl_NewBooleanObj(ctx->compiled_model != NULL));

        /* Get input/output counts */
        if (ctx->model) {
            size_t input_size = 0, output_size = 0;
            ov_model_inputs_size(ctx->model, &input_size);
            ov_model_outputs_size(ctx->model, &output_size);
            Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("inputs", -1),
                           Tcl_NewWideIntObj(input_size));
            Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("outputs", -1),
                           Tcl_NewWideIntObj(output_size));
        }

        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "create_request") == 0) {
        /* Create an inference request */
        if (!ctx->compiled_model) {
            Tcl_AppendResult(interp, "model not compiled", NULL);
            return TCL_ERROR;
        }

        InferCtx *inf_ctx = (InferCtx*)ckalloc(sizeof(InferCtx));
        memset(inf_ctx, 0, sizeof(*inf_ctx));
        inf_ctx->model_ctx = ctx;
        inf_ctx->interp = interp;
        inf_ctx->closed = 0;

        ov_status_e status = ov_compiled_model_create_infer_request(
            ctx->compiled_model, &inf_ctx->request);
        if (status != OK) {
            ckfree((char*)inf_ctx);
            return SetOVError(interp, "Failed to create infer request", status);
        }

        /* Create unique command name */
        static int infer_counter = 0;
        char namebuf[64];
        sprintf(namebuf, "gec_infer%d", ++infer_counter);
        Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, -1);
        Tcl_IncrRefCount(nameObj);
        inf_ctx->cmdname = nameObj;

        Tcl_CreateObjCommand(interp, namebuf, InferObjCmd,
                             (ClientData)inf_ctx, infer_delete);

        Tcl_SetObjResult(interp, nameObj);
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub,
                     "\": must be info, create_request, or close", NULL);
    return TCL_ERROR;
}

/* Infer request object command dispatcher */
static int InferObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    InferCtx *ctx = (InferCtx*)cd;

    if (!ctx || ctx->closed || !ctx->request) {
        Tcl_AppendResult(interp, "infer request closed or invalid", NULL);
        return TCL_ERROR;
    }

    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }

    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub, "set_input") == 0) {
        /* set_input index data_list */
        if (objc != 4) {
            Tcl_WrongNumArgs(interp, 2, objv, "index data_list");
            return TCL_ERROR;
        }

        int idx;
        if (Tcl_GetIntFromObj(interp, objv[2], &idx) != TCL_OK) {
            return TCL_ERROR;
        }

        /* Get the list of int64 values */
        Tcl_Size list_len;
        if (Tcl_ListObjLength(interp, objv[3], &list_len) != TCL_OK) {
            return TCL_ERROR;
        }

        /* Create tensor with shape [1, list_len] for typical BERT-style input */
        int64_t dims[2] = {1, (int64_t)list_len};
        ov_shape_t shape;
        ov_status_e status = ov_shape_create(2, dims, &shape);
        if (status != OK) {
            return SetOVError(interp, "Failed to create shape", status);
        }

        ov_tensor_t *tensor = NULL;
        status = ov_tensor_create(I64, shape, &tensor);
        ov_shape_free(&shape);
        if (status != OK) {
            return SetOVError(interp, "Failed to create tensor", status);
        }

        /* Fill tensor data */
        int64_t *data = NULL;
        status = ov_tensor_data(tensor, (void**)&data);
        if (status != OK) {
            ov_tensor_free(tensor);
            return SetOVError(interp, "Failed to get tensor data", status);
        }

        for (Tcl_Size i = 0; i < list_len; i++) {
            Tcl_Obj *elem;
            Tcl_ListObjIndex(interp, objv[3], i, &elem);
            Tcl_WideInt val;
            if (Tcl_GetWideIntFromObj(interp, elem, &val) != TCL_OK) {
                ov_tensor_free(tensor);
                return TCL_ERROR;
            }
            data[i] = (int64_t)val;
        }

        /* Set the tensor as input */
        status = ov_infer_request_set_input_tensor_by_index(ctx->request, idx, tensor);
        ov_tensor_free(tensor);  /* Request keeps a copy */
        if (status != OK) {
            return SetOVError(interp, "Failed to set input tensor", status);
        }

        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;

    } else if (strcmp(sub, "infer") == 0) {
        /* Run synchronous inference */
        ov_status_e status = ov_infer_request_infer(ctx->request);
        if (status != OK) {
            return SetOVError(interp, "Inference failed", status);
        }
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;

    } else if (strcmp(sub, "get_output") == 0) {
        /* get_output index -> returns list of floats */
        if (objc != 3) {
            Tcl_WrongNumArgs(interp, 2, objv, "index");
            return TCL_ERROR;
        }

        int idx;
        if (Tcl_GetIntFromObj(interp, objv[2], &idx) != TCL_OK) {
            return TCL_ERROR;
        }

        ov_tensor_t *output = NULL;
        ov_status_e status = ov_infer_request_get_output_tensor_by_index(
            ctx->request, idx, &output);
        if (status != OK) {
            return SetOVError(interp, "Failed to get output tensor", status);
        }

        /* Get tensor shape and data */
        ov_shape_t shape;
        status = ov_tensor_get_shape(output, &shape);
        if (status != OK) {
            ov_tensor_free(output);
            return SetOVError(interp, "Failed to get output shape", status);
        }

        size_t total_size = 0;
        status = ov_tensor_get_size(output, &total_size);
        if (status != OK) {
            ov_shape_free(&shape);
            ov_tensor_free(output);
            return SetOVError(interp, "Failed to get output size", status);
        }

        ov_element_type_e elem_type;
        status = ov_tensor_get_element_type(output, &elem_type);
        if (status != OK) {
            ov_shape_free(&shape);
            ov_tensor_free(output);
            return SetOVError(interp, "Failed to get element type", status);
        }

        void *data = NULL;
        status = ov_tensor_data(output, &data);
        if (status != OK) {
            ov_shape_free(&shape);
            ov_tensor_free(output);
            return SetOVError(interp, "Failed to get output data", status);
        }

        /* Build result dict with shape and data */
        Tcl_Obj *result = Tcl_NewDictObj();

        /* Add shape */
        Tcl_Obj *shape_list = Tcl_NewListObj(0, NULL);
        for (int64_t i = 0; i < shape.rank; i++) {
            Tcl_ListObjAppendElement(interp, shape_list,
                                     Tcl_NewWideIntObj(shape.dims[i]));
        }
        Tcl_DictObjPut(interp, result, Tcl_NewStringObj("shape", -1), shape_list);

        /* Add data based on element type */
        Tcl_Obj *data_list = Tcl_NewListObj(0, NULL);
        if (elem_type == F32) {
            float *fdata = (float*)data;
            for (size_t i = 0; i < total_size; i++) {
                Tcl_ListObjAppendElement(interp, data_list,
                                         Tcl_NewDoubleObj(fdata[i]));
            }
        } else if (elem_type == I64) {
            int64_t *idata = (int64_t*)data;
            for (size_t i = 0; i < total_size; i++) {
                Tcl_ListObjAppendElement(interp, data_list,
                                         Tcl_NewWideIntObj(idata[i]));
            }
        } else if (elem_type == I32) {
            int32_t *idata = (int32_t*)data;
            for (size_t i = 0; i < total_size; i++) {
                Tcl_ListObjAppendElement(interp, data_list,
                                         Tcl_NewIntObj(idata[i]));
            }
        } else {
            /* Return raw bytes for unknown types */
            size_t byte_size = 0;
            ov_tensor_get_byte_size(output, &byte_size);
            Tcl_Obj *bytes = Tcl_NewByteArrayObj((unsigned char*)data, byte_size);
            Tcl_DictObjPut(interp, result, Tcl_NewStringObj("raw_data", -1), bytes);
        }
        Tcl_DictObjPut(interp, result, Tcl_NewStringObj("data", -1), data_list);

        ov_shape_free(&shape);
        ov_tensor_free(output);

        Tcl_SetObjResult(interp, result);
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub,
                     "\": must be set_input, infer, get_output, or close", NULL);
    return TCL_ERROR;
}

/* Tcl command: gec::load_model -path <path> ?-device <device>? */
static int GecLoadModelCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;

    const char *model_path = NULL;
    const char *device_name = "CPU";  /* Default to CPU */

    /* Parse arguments */
    int i = 1;
    while (i < objc) {
        const char *opt = Tcl_GetString(objv[i]);
        if (strcmp(opt, "-path") == 0 && i+1 < objc) {
            model_path = Tcl_GetString(objv[++i]);
        } else if (strcmp(opt, "-device") == 0 && i+1 < objc) {
            device_name = Tcl_GetString(objv[++i]);
        } else {
            Tcl_AppendResult(interp, "unknown option ", opt,
                             ": must be -path or -device", NULL);
            return TCL_ERROR;
        }
        i++;
    }

    if (!model_path) {
        Tcl_AppendResult(interp, "missing required option -path", NULL);
        return TCL_ERROR;
    }

    /* Initialize core if needed */
    if (init_core(interp) != TCL_OK) {
        return TCL_ERROR;
    }

    /* Create model context */
    ModelCtx *ctx = (ModelCtx*)ckalloc(sizeof(ModelCtx));
    memset(ctx, 0, sizeof(*ctx));
    ctx->interp = interp;

    /* Store paths */
    ctx->model_path = (char*)ckalloc(strlen(model_path) + 1);
    strcpy(ctx->model_path, model_path);
    ctx->device_name = (char*)ckalloc(strlen(device_name) + 1);
    strcpy(ctx->device_name, device_name);

    /* Read model from file (ONNX, IR, etc.) */
    ov_status_e status = ov_core_read_model(g_core, model_path, NULL, &ctx->model);
    if (status != OK) {
        ckfree(ctx->model_path);
        ckfree(ctx->device_name);
        ckfree((char*)ctx);
        release_core();
        return SetOVError(interp, "Failed to read model", status);
    }

    /* Compile model for target device - NPU needs special config */
    if (strcmp(device_name, "NPU") == 0) {
        /* Set NPU compiler type to PLUGIN before compiling */
        status = ov_core_set_property(g_core, device_name,
                                      "NPU_COMPILER_TYPE", "PLUGIN");
        if (status != OK) {
            ov_model_free(ctx->model);
            ckfree(ctx->model_path);
            ckfree(ctx->device_name);
            ckfree((char*)ctx);
            release_core();
            return SetOVError(interp, "Failed to set NPU compiler type", status);
        }
    }
    status = ov_core_compile_model(g_core, ctx->model, device_name, 0,
                                   &ctx->compiled_model);
    if (status != OK) {
        ov_model_free(ctx->model);
        ckfree(ctx->model_path);
        ckfree(ctx->device_name);
        ckfree((char*)ctx);
        release_core();
        return SetOVError(interp, "Failed to compile model", status);
    }

    /* Create unique Tcl command name */
    static int model_counter = 0;
    char namebuf[64];
    sprintf(namebuf, "gec_model%d", ++model_counter);
    Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, -1);
    Tcl_IncrRefCount(nameObj);
    ctx->cmdname = nameObj;

    /* Create Tcl command object */
    Tcl_CreateObjCommand(interp, namebuf, ModelObjCmd, (ClientData)ctx, model_delete);

    /* Return command name */
    Tcl_SetObjResult(interp, nameObj);
    return TCL_OK;
}

/* Tcl command: gec::version */
static int GecVersionCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    (void)objc;
    (void)objv;

    ov_version_t version;
    ov_status_e status = ov_get_openvino_version(&version);
    if (status != OK) {
        return SetOVError(interp, "Failed to get OpenVINO version", status);
    }

    Tcl_Obj *dict = Tcl_NewDictObj();
    Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("build", -1),
                   Tcl_NewStringObj(version.buildNumber ? version.buildNumber : "", -1));
    Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("description", -1),
                   Tcl_NewStringObj(version.description ? version.description : "", -1));

    ov_version_free(&version);

    Tcl_SetObjResult(interp, dict);
    return TCL_OK;
}

/* Tcl command: gec::devices */
static int GecDevicesCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    (void)objc;
    (void)objv;

    /* Ensure core is initialized */
    if (init_core(interp) != TCL_OK) {
        return TCL_ERROR;
    }

    ov_available_devices_t devices;
    ov_status_e status = ov_core_get_available_devices(g_core, &devices);
    if (status != OK) {
        release_core();
        return SetOVError(interp, "Failed to get available devices", status);
    }

    Tcl_Obj *list = Tcl_NewListObj(0, NULL);
    for (size_t i = 0; i < devices.size; i++) {
        Tcl_ListObjAppendElement(interp, list,
                                 Tcl_NewStringObj(devices.devices[i], -1));
    }

    ov_available_devices_free(&devices);
    release_core();

    Tcl_SetObjResult(interp, list);
    return TCL_OK;
}

} ;# end of ccode

critcl::cinit {
    /* Create package commands */
    Tcl_CreateObjCommand(interp, "gec::load_model", GecLoadModelCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "gec::version", GecVersionCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "gec::devices", GecDevicesCmd, NULL, NULL);
} ""

package provide gec 1.0
