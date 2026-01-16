# ct2.tcl - Critcl CTranslate2 bindings for grammar correction
# Provides T5 seq2seq translation using CTranslate2 + SentencePiece tokenization
package require critcl 3.1

# Paths to libraries
set ct2_include $::env(HOME)/.local/include
set ct2_lib $::env(HOME)/.local/lib64
set sp_include $::env(HOME)/.local/include
set sp_lib $::env(HOME)/.local/lib

critcl::cheaders -I$ct2_include -I$sp_include
critcl::clibraries -L$ct2_lib -lctranslate2 -L$sp_lib -lsentencepiece -lstdc++
critcl::clibraries -L/usr/lib -ltclstub8.6

# C++17 required for CTranslate2
# -x c++ tells gcc to compile as C++ regardless of file extension
critcl::cflags -x c++ -std=c++17

namespace eval ct2 {}

critcl::ccode {
#include <tcl.h>
#include <string.h>
#include <stdlib.h>

// CTranslate2 and SentencePiece C++ headers
#include <ctranslate2/translator.h>
#include <ctranslate2/models/model.h>
#include <sentencepiece_processor.h>

#include <string>
#include <vector>
#include <memory>

// Grammar model context
typedef struct {
    ctranslate2::Translator* translator;
    sentencepiece::SentencePieceProcessor* tokenizer;
    char* model_path;
    Tcl_Obj* cmdname;
    Tcl_Interp* interp;
} GrammarCtx;

// Forward declarations
static int GrammarObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]);
static void grammar_delete(ClientData cd);

// Cleanup when command is deleted
static void grammar_delete(ClientData cd) {
    GrammarCtx *ctx = (GrammarCtx*)cd;
    if (!ctx) return;

    if (ctx->translator) {
        delete ctx->translator;
        ctx->translator = NULL;
    }
    if (ctx->tokenizer) {
        delete ctx->tokenizer;
        ctx->tokenizer = NULL;
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

// Grammar model object command
static int GrammarObjCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    GrammarCtx *ctx = (GrammarCtx*)cd;

    if (objc < 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "subcommand ?args?");
        return TCL_ERROR;
    }

    const char *sub = Tcl_GetString(objv[1]);

    if (strcmp(sub, "correct") == 0) {
        // correct <text> - apply grammar correction
        if (objc != 3) {
            Tcl_WrongNumArgs(interp, 2, objv, "text");
            return TCL_ERROR;
        }

        const char *input_text = Tcl_GetString(objv[2]);

        try {
            // Tokenize with SentencePiece
            std::vector<std::string> tokens;
            ctx->tokenizer->Encode(input_text, &tokens);

            // Add EOS token for T5
            tokens.push_back("</s>");

            // Translate (single batch)
            std::vector<std::vector<std::string>> batch = {tokens};
            ctranslate2::TranslationOptions options;
            options.beam_size = 1;  // Greedy for speed
            options.max_decoding_length = 256;

            auto results = ctx->translator->translate_batch(batch, options);

            if (results.empty() || results[0].output().empty()) {
                // Return original if translation failed
                Tcl_SetObjResult(interp, objv[2]);
                return TCL_OK;
            }

            // Detokenize output
            std::string output;
            ctx->tokenizer->Decode(results[0].output(), &output);

            Tcl_SetObjResult(interp, Tcl_NewStringObj(output.c_str(), -1));
            return TCL_OK;

        } catch (const std::exception& e) {
            Tcl_AppendResult(interp, "Grammar correction failed: ", e.what(), NULL);
            return TCL_ERROR;
        }

    } else if (strcmp(sub, "info") == 0) {
        // Return model information
        Tcl_Obj *dict = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("path", -1),
                       Tcl_NewStringObj(ctx->model_path, -1));
        Tcl_DictObjPut(interp, dict, Tcl_NewStringObj("device", -1),
                       Tcl_NewStringObj("cpu", -1));
        Tcl_SetObjResult(interp, dict);
        return TCL_OK;

    } else if (strcmp(sub, "close") == 0) {
        Tcl_DeleteCommand(interp, Tcl_GetString(objv[0]));
        Tcl_SetObjResult(interp, Tcl_NewStringObj("ok", -1));
        return TCL_OK;
    }

    Tcl_AppendResult(interp, "unknown subcommand \"", sub,
                     "\": must be correct, info, or close", NULL);
    return TCL_ERROR;
}

// ct2::load_model -path <model_dir>
static int CT2LoadModelCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;

    const char *model_path = NULL;

    // Parse arguments
    int i = 1;
    while (i < objc) {
        const char *opt = Tcl_GetString(objv[i]);
        if (strcmp(opt, "-path") == 0 && i+1 < objc) {
            model_path = Tcl_GetString(objv[++i]);
        } else {
            Tcl_AppendResult(interp, "unknown option ", opt, ": must be -path", NULL);
            return TCL_ERROR;
        }
        i++;
    }

    if (!model_path) {
        Tcl_AppendResult(interp, "missing required option -path", NULL);
        return TCL_ERROR;
    }

    // Create context
    GrammarCtx *ctx = (GrammarCtx*)ckalloc(sizeof(GrammarCtx));
    memset(ctx, 0, sizeof(*ctx));
    ctx->interp = interp;

    // Store path
    ctx->model_path = (char*)ckalloc(strlen(model_path) + 1);
    strcpy(ctx->model_path, model_path);

    try {
        // Load SentencePiece tokenizer
        ctx->tokenizer = new sentencepiece::SentencePieceProcessor();
        std::string sp_path = std::string(model_path) + "/spiece.model";
        auto status = ctx->tokenizer->Load(sp_path);
        if (!status.ok()) {
            delete ctx->tokenizer;
            ctx->tokenizer = NULL;
            ckfree(ctx->model_path);
            ckfree((char*)ctx);
            Tcl_AppendResult(interp, "Failed to load tokenizer: ", status.ToString().c_str(), NULL);
            return TCL_ERROR;
        }

        // Load CTranslate2 translator
        // API: Translator(model_path, device, compute_type, device_indices, tensor_parallel, config)
        // Use AUTO to let CT2 pick best available (INT8 requires specific CPU support)
        ctx->translator = new ctranslate2::Translator(
            std::string(model_path),
            ctranslate2::Device::CPU,
            ctranslate2::ComputeType::AUTO);

    } catch (const std::exception& e) {
        if (ctx->tokenizer) delete ctx->tokenizer;
        if (ctx->translator) delete ctx->translator;
        ckfree(ctx->model_path);
        ckfree((char*)ctx);
        Tcl_AppendResult(interp, "Failed to load model: ", e.what(), NULL);
        return TCL_ERROR;
    }

    // Create unique command name
    static int model_counter = 0;
    char namebuf[64];
    sprintf(namebuf, "ct2_grammar%d", ++model_counter);
    Tcl_Obj *nameObj = Tcl_NewStringObj(namebuf, -1);
    Tcl_IncrRefCount(nameObj);
    ctx->cmdname = nameObj;

    // Create Tcl command
    Tcl_CreateObjCommand(interp, namebuf, GrammarObjCmd, (ClientData)ctx, grammar_delete);

    Tcl_SetObjResult(interp, nameObj);
    return TCL_OK;
}

} ;# end of ccode

critcl::cinit {
    Tcl_CreateObjCommand(interp, "ct2::load_model", CT2LoadModelCmd, NULL, NULL);
} ""

package provide ct2 1.0
