# GEC Critcl OpenVINO Implementation Plan

## Overview

Create Tcl bindings to OpenVINO C API for grammar error correction on Intel NPU.

## Architecture

```
src/gec/
├── gec.tcl              # Critcl bindings + Tcl API
├── wordpiece.c          # WordPiece tokenizer implementation
├── openvino_infer.c     # OpenVINO inference wrapper
├── vocab.txt            # ELECTRA vocabulary (copied from model)
└── pkgIndex.tcl         # Package index (auto-generated)
```

## Phase 1: OpenVINO C API Bindings

### 1.1 Core OpenVINO Functions Needed

```c
// Model loading
ov_core_create()
ov_core_read_model()
ov_core_compile_model()

// Inference
ov_infer_request_create()
ov_infer_request_set_input_tensor()
ov_infer_request_infer()
ov_infer_request_get_output_tensor()

// Tensor operations
ov_tensor_create()
ov_tensor_data()
```

### 1.2 Critcl Structure

```tcl
package require critcl

critcl::clibraries -L/home/john/pkg/openvino-src/bin/intel64/Release -lopenvino
critcl::cflags -I/home/john/pkg/openvino-src/runtime/include

critcl::ccode {
    #include <openvino/c/openvino.h>
    // Static model handles
    static ov_core_t* core = NULL;
    static ov_compiled_model_t* electra_model = NULL;
    static ov_compiled_model_t* punct_model = NULL;
}
```

## Phase 2: WordPiece Tokenizer

### 2.1 Algorithm

1. Load vocab.txt into hash table (token -> id)
2. For input text:
   - Lowercase and split on whitespace
   - For each word, greedily match longest prefix in vocab
   - If no match, output [UNK] token
   - Continue with "##" + remaining suffix
3. Add [CLS] at start, [SEP] at end
4. Pad to fixed length (64 tokens)

### 2.2 Data Structures

```c
typedef struct {
    Tcl_HashTable vocab;      // token string -> token id
    int vocab_size;
    int unk_id;               // [UNK] token id
    int cls_id;               // [CLS] token id
    int sep_id;               // [SEP] token id
    int pad_id;               // [PAD] token id
    int mask_id;              // [MASK] token id
} WordPieceTokenizer;
```

## Phase 3: Inference Pipeline

### 3.1 ELECTRA Homophone Correction

```tcl
proc gec::fix_homophones {text} {
    # 1. Tokenize with WordPiece
    # 2. For each token, check if it's a known homophone
    # 3. Mask the token, run inference
    # 4. Compare P(original) vs P(alternative)
    # 5. Replace if alternative has higher probability
}
```

### 3.2 DistilBERT Punctuation + Capitalization

```tcl
proc gec::add_punctuation {text} {
    # 1. Tokenize
    # 2. Run token classification inference
    # 3. Map label IDs to punctuation/caps actions
    # 4. Apply corrections
}
```

## Phase 4: Tcl API

```tcl
package require gec

# Initialize with model paths
gec::init \
    -electra /path/to/electra-small-generator.onnx \
    -punct /path/to/distilbert-punct-cap.onnx \
    -device NPU

# Correct text (full pipeline)
set corrected [gec::correct "i went to there house"]
# Returns: "I went to their house."

# Individual stages
set punctuated [gec::punctuate "i went to the store"]
set fixed [gec::fix_homophones "I went to there house."]
```

## Implementation Order

1. **Phase 1**: Basic OpenVINO loading and inference
   - [ ] Create gec.tcl with critcl skeleton
   - [ ] Implement ov_core initialization
   - [ ] Implement model loading
   - [ ] Test with simple tensor input

2. **Phase 2**: WordPiece tokenizer
   - [ ] Implement vocab.txt loading
   - [ ] Implement tokenization algorithm
   - [ ] Implement detokenization
   - [ ] Test roundtrip

3. **Phase 3**: ELECTRA integration
   - [ ] Implement MLM inference
   - [ ] Implement homophone detection
   - [ ] Implement probability comparison
   - [ ] Test accuracy

4. **Phase 4**: DistilBERT integration
   - [ ] Implement token classification inference
   - [ ] Implement label mapping
   - [ ] Test punctuation output

5. **Phase 5**: Full pipeline
   - [ ] Combine stages
   - [ ] Add error handling
   - [ ] Performance optimization

## Dependencies

- OpenVINO 2026.0 (already built at ~/pkg/openvino-src)
- NPU driver (already built at ~/pkg/linux-npu-driver)
- Models:
  - models/gec/electra-small-generator.onnx (67 MB)
  - models/gec/distilbert-punct-cap.onnx (254 MB)

## Environment

```bash
export LD_LIBRARY_PATH=/home/john/pkg/linux-npu-driver/build/lib:/home/john/pkg/openvino-src/bin/intel64/Release
```

## References

- [OpenVINO C API](https://docs.openvino.ai/2024/api/c_cpp_api/group__ov__c__api.html)
- [Critcl Documentation](https://andreas-kupries.github.io/critcl/)
- [WordPiece Algorithm](https://huggingface.co/learn/nlp-course/chapter6/6)
