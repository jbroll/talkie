# wordpiece.tcl - WordPiece tokenizer for BERT/ELECTRA models
# Provides fast tokenization using critcl C implementation
package require critcl 3.1

# Link against Tcl stubs library
critcl::clibraries -L/usr/lib -ltclstub8.6

namespace eval wordpiece {}

critcl::ccode {
#include <tcl.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

/* WordPiece tokenizer state */
static Tcl_HashTable g_vocab;     /* token string -> id */
static char **g_id_to_token = NULL;  /* id -> token string */
static int g_vocab_size = 0;
static int g_vocab_loaded = 0;

/* Special token IDs (BERT standard) */
#define PAD_ID 0
#define UNK_ID 100
#define CLS_ID 101
#define SEP_ID 102
#define MASK_ID 103

/* Get token ID from string, returns UNK_ID if not found */
static int get_token_id(const char *token) {
    Tcl_HashEntry *entry = Tcl_FindHashEntry(&g_vocab, token);
    if (entry == NULL) return UNK_ID;
    return (int)(intptr_t)Tcl_GetHashValue(entry);
}

/* Load vocabulary file: one token per line, line number = token id */
static int WpLoadVocabCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "vocab_file");
        return TCL_ERROR;
    }

    const char *path = Tcl_GetString(objv[1]);

    /* Open file */
    Tcl_Channel chan = Tcl_OpenFileChannel(interp, path, "r", 0);
    if (chan == NULL) return TCL_ERROR;
    Tcl_SetChannelOption(interp, chan, "-encoding", "utf-8");

    /* Clear existing vocab if any */
    if (g_vocab_loaded) {
        Tcl_DeleteHashTable(&g_vocab);
        for (int i = 0; i < g_vocab_size; i++) {
            if (g_id_to_token[i]) ckfree(g_id_to_token[i]);
        }
        ckfree((char*)g_id_to_token);
        g_vocab_loaded = 0;
    }

    /* Initialize hash table */
    Tcl_InitHashTable(&g_vocab, TCL_STRING_KEYS);

    /* First pass: count lines */
    Tcl_Obj *lineObj = Tcl_NewObj();
    Tcl_IncrRefCount(lineObj);
    int line_count = 0;
    while (Tcl_GetsObj(chan, lineObj) >= 0) {
        line_count++;
        Tcl_SetObjLength(lineObj, 0);
    }
    Tcl_Seek(chan, 0, SEEK_SET);

    /* Allocate id_to_token array */
    g_id_to_token = (char**)ckalloc(sizeof(char*) * line_count);
    memset(g_id_to_token, 0, sizeof(char*) * line_count);

    /* Second pass: load tokens */
    int id = 0;
    while (Tcl_GetsObj(chan, lineObj) >= 0) {
        Tcl_Size len;
        const char *token = Tcl_GetStringFromObj(lineObj, &len);

        /* Store token -> id */
        int isNew;
        Tcl_HashEntry *entry = Tcl_CreateHashEntry(&g_vocab, token, &isNew);
        if (isNew) {
            Tcl_SetHashValue(entry, (ClientData)(intptr_t)id);
        }

        /* Store id -> token */
        g_id_to_token[id] = (char*)ckalloc(len + 1);
        memcpy(g_id_to_token[id], token, len + 1);

        id++;
        Tcl_SetObjLength(lineObj, 0);
    }

    Tcl_DecrRefCount(lineObj);
    Tcl_Close(interp, chan);

    g_vocab_size = id;
    g_vocab_loaded = 1;

    Tcl_SetObjResult(interp, Tcl_NewIntObj(g_vocab_size));
    return TCL_OK;
}

/* Check if character is whitespace or punctuation for tokenization */
static int is_split_char(int c) {
    if (c <= 32) return 1;  /* whitespace */
    if (c >= 33 && c <= 47) return 1;  /* !"#$%&'()*+,-./ */
    if (c >= 58 && c <= 64) return 1;  /* :;<=>?@ */
    if (c >= 91 && c <= 96) return 1;  /* [\]^_` */
    if (c >= 123 && c <= 126) return 1;  /* {|}~ */
    return 0;
}

/* Tokenize text using WordPiece algorithm */
static int WpTokenizeCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 2 && objc != 3) {
        Tcl_WrongNumArgs(interp, 1, objv, "text ?max_len?");
        return TCL_ERROR;
    }

    if (!g_vocab_loaded) {
        Tcl_SetResult(interp, "vocabulary not loaded, call wordpiece::load first", TCL_STATIC);
        return TCL_ERROR;
    }

    Tcl_Size text_len;
    const char *text = Tcl_GetStringFromObj(objv[1], &text_len);

    int max_len = 64;
    if (objc == 3 && Tcl_GetIntFromObj(interp, objv[2], &max_len) != TCL_OK) {
        return TCL_ERROR;
    }

    /* Result list for token IDs */
    Tcl_Obj *result = Tcl_NewListObj(0, NULL);
    int token_count = 1;  /* Start with [CLS] */
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(CLS_ID));

    /* Temporary buffer for word building */
    char word[256];
    char subword[260];  /* word + "##" prefix */
    int word_len = 0;

    /* Process text character by character */
    for (Tcl_Size i = 0; i <= text_len && token_count < max_len - 1; i++) {
        int c = (i < text_len) ? (unsigned char)text[i] : ' ';

        /* Convert to lowercase */
        if (c >= 'A' && c <= 'Z') c = c + 32;

        if (is_split_char(c)) {
            /* End of word - tokenize it */
            if (word_len > 0) {
                word[word_len] = '\0';

                /* WordPiece: greedy longest match */
                int pos = 0;
                int first_piece = 1;
                while (pos < word_len && token_count < max_len - 1) {
                    int best_end = pos;

                    /* Try longest match first */
                    for (int end = word_len; end > pos; end--) {
                        if (first_piece) {
                            memcpy(subword, word + pos, end - pos);
                            subword[end - pos] = '\0';
                        } else {
                            subword[0] = '#';
                            subword[1] = '#';
                            memcpy(subword + 2, word + pos, end - pos);
                            subword[2 + end - pos] = '\0';
                        }

                        if (get_token_id(subword) != UNK_ID) {
                            best_end = end;
                            break;
                        }
                    }

                    if (best_end == pos) {
                        /* No match found, use [UNK] for whole word */
                        Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(UNK_ID));
                        token_count++;
                        break;
                    }

                    /* Add the matched subword */
                    if (first_piece) {
                        memcpy(subword, word + pos, best_end - pos);
                        subword[best_end - pos] = '\0';
                    } else {
                        subword[0] = '#';
                        subword[1] = '#';
                        memcpy(subword + 2, word + pos, best_end - pos);
                        subword[2 + best_end - pos] = '\0';
                    }

                    int id = get_token_id(subword);
                    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(id));
                    token_count++;

                    pos = best_end;
                    first_piece = 0;
                }

                word_len = 0;
            }

            /* Handle punctuation as separate token */
            if (c > 32 && i < text_len) {
                char punct[2] = {(char)c, '\0'};
                int id = get_token_id(punct);
                if (id != UNK_ID && token_count < max_len - 1) {
                    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(id));
                    token_count++;
                }
            }
        } else {
            /* Add character to current word */
            if (word_len < 255) {
                word[word_len++] = (char)c;
            }
        }
    }

    /* Add [SEP] token */
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(SEP_ID));
    token_count++;

    /* Pad to max_len */
    while (token_count < max_len) {
        Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(PAD_ID));
        token_count++;
    }

    Tcl_SetObjResult(interp, result);
    return TCL_OK;
}

/* Check if token is punctuation that attaches to previous word */
static int is_attach_left_punct(const char *token) {
    if (!token || !token[0]) return 0;
    /* Single char punctuation that attaches left */
    if (token[1] == '\0') {
        char c = token[0];
        return c == '.' || c == ',' || c == '!' || c == '?' ||
               c == ':' || c == ';' || c == ')' || c == ']' ||
               c == '\'' || c == '"';
    }
    return 0;
}

/* Check if token is punctuation that should not have space after */
static int is_attach_right_punct(const char *token) {
    if (!token || !token[0]) return 0;
    if (token[1] == '\0') {
        char c = token[0];
        return c == '(' || c == '[' || c == '\'' || c == '"';
    }
    return 0;
}

/* Detokenize: convert token IDs back to text */
static int WpDetokenizeCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "token_ids");
        return TCL_ERROR;
    }

    if (!g_vocab_loaded) {
        Tcl_SetResult(interp, "vocabulary not loaded, call wordpiece::load first", TCL_STATIC);
        return TCL_ERROR;
    }

    Tcl_Size list_len;
    if (Tcl_ListObjLength(interp, objv[1], &list_len) != TCL_OK) {
        return TCL_ERROR;
    }

    Tcl_DString result;
    Tcl_DStringInit(&result);

    int need_space = 0;
    int prev_attach_right = 0;
    for (Tcl_Size i = 0; i < list_len; i++) {
        Tcl_Obj *elem;
        Tcl_ListObjIndex(interp, objv[1], i, &elem);

        int id;
        if (Tcl_GetIntFromObj(interp, elem, &id) != TCL_OK) {
            Tcl_DStringFree(&result);
            return TCL_ERROR;
        }

        /* Skip special tokens */
        if (id == PAD_ID || id == CLS_ID || id == SEP_ID || id == MASK_ID) {
            continue;
        }

        if (id < 0 || id >= g_vocab_size) {
            continue;
        }

        const char *token = g_id_to_token[id];
        if (!token) continue;

        /* Handle ## continuation tokens (no space) */
        if (token[0] == '#' && token[1] == '#') {
            Tcl_DStringAppend(&result, token + 2, -1);
            prev_attach_right = 0;
        } else {
            /* Add space unless: at start, punctuation attaches left, or previous attaches right */
            int attach_left = is_attach_left_punct(token);
            if (need_space && !attach_left && !prev_attach_right) {
                Tcl_DStringAppend(&result, " ", 1);
            }
            Tcl_DStringAppend(&result, token, -1);
            prev_attach_right = is_attach_right_punct(token);
        }
        need_space = 1;
    }

    Tcl_SetObjResult(interp, Tcl_NewStringObj(Tcl_DStringValue(&result), -1));
    Tcl_DStringFree(&result);
    return TCL_OK;
}

/* Get attention mask: 1 for non-padding tokens, 0 for padding */
static int WpAttentionMaskCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "token_ids");
        return TCL_ERROR;
    }

    Tcl_Size list_len;
    if (Tcl_ListObjLength(interp, objv[1], &list_len) != TCL_OK) {
        return TCL_ERROR;
    }

    Tcl_Obj *result = Tcl_NewListObj(0, NULL);
    for (Tcl_Size i = 0; i < list_len; i++) {
        Tcl_Obj *elem;
        Tcl_ListObjIndex(interp, objv[1], i, &elem);

        int id;
        if (Tcl_GetIntFromObj(interp, elem, &id) != TCL_OK) {
            return TCL_ERROR;
        }

        /* 1 for non-padding, 0 for padding */
        Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(id != PAD_ID ? 1 : 0));
    }

    Tcl_SetObjResult(interp, result);
    return TCL_OK;
}

/* Get token string from ID */
static int WpIdToTokenCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "id");
        return TCL_ERROR;
    }

    if (!g_vocab_loaded) {
        Tcl_SetResult(interp, "vocabulary not loaded, call wordpiece::load first", TCL_STATIC);
        return TCL_ERROR;
    }

    int id;
    if (Tcl_GetIntFromObj(interp, objv[1], &id) != TCL_OK) {
        return TCL_ERROR;
    }

    if (id < 0 || id >= g_vocab_size || !g_id_to_token[id]) {
        Tcl_SetResult(interp, "[UNK]", TCL_STATIC);
    } else {
        Tcl_SetObjResult(interp, Tcl_NewStringObj(g_id_to_token[id], -1));
    }
    return TCL_OK;
}

/* Get token ID from string */
static int WpTokenToIdCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "token");
        return TCL_ERROR;
    }

    if (!g_vocab_loaded) {
        Tcl_SetResult(interp, "vocabulary not loaded, call wordpiece::load first", TCL_STATIC);
        return TCL_ERROR;
    }

    const char *token = Tcl_GetString(objv[1]);
    int id = get_token_id(token);
    Tcl_SetObjResult(interp, Tcl_NewIntObj(id));
    return TCL_OK;
}

/* Get vocab size */
static int WpVocabSizeCmd(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    (void)cd;
    (void)objv;
    if (objc != 1) {
        Tcl_WrongNumArgs(interp, 1, objv, "");
        return TCL_ERROR;
    }
    Tcl_SetObjResult(interp, Tcl_NewIntObj(g_vocab_size));
    return TCL_OK;
}

}

critcl::cinit {
    Tcl_CreateObjCommand(interp, "wordpiece::load", WpLoadVocabCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "wordpiece::encode", WpTokenizeCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "wordpiece::decode", WpDetokenizeCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "wordpiece::attention_mask", WpAttentionMaskCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "wordpiece::id_to_token", WpIdToTokenCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "wordpiece::token_to_id", WpTokenToIdCmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "wordpiece::vocab_size", WpVocabSizeCmd, NULL, NULL);
} ""

package provide wordpiece 1.0
