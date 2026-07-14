# STT Engine API + sherpa-onnx critcl binding — Design

**Date:** 2026-07-14
**Status:** Approved for planning

## Overview

Talkie's speech-to-text is pluggable but the plugin contract is implicit and split
across two dispatch paths (`critcl` in-process vs `coprocess` Python side-service),
branched inline in five places in `src/engine.tcl`. We are adding a fourth-generation
engine (sherpa-onnx) as a real in-process critcl binding, and while doing so we
formalize a single common API that all candidate engines — **Vosk, sherpa-onnx,
whisper.cpp, OpenVINO GenAI** — can implement.

The formalization also fixes a live bug: **endpoint detection fails in noisy
environments** because finalization is gated solely on an energy-threshold VAD
(`audiolevel > audio_threshold`), whose silence never triggers when the room noise
floor sits above the pauses in speech. The new API carries an **end-of-utterance
signal** from engines that can self-detect it — in this prototype, sherpa-onnx's
streaming `IsEndpoint` (Vosk's native Kaldi endpointer is a candidate but is not yet
wrapped, so Vosk uses the fallback) — and an app-side fallback for engines that
cannot.

## Goals

1. Define one common engine contract that Vosk, sherpa-onnx, whisper.cpp, and
   OpenVINO GenAI can all satisfy — spanning both streaming and batch engine shapes.
2. Add an **end-of-utterance signal** to the contract so noise-robust,
   recognizer-driven endpointing is available where the engine supports it.
3. Prototype **sherpa-onnx as an in-process critcl binding** (streaming Zipformer
   transducer), proving the contract with a real C binding and removing the Python
   side-service dependency for this engine.
4. Collapse the five scattered `critcl`-vs-`coprocess` branches into one dispatch
   layer (scoped to the call sites the endpoint change already touches).

## Non-Goals (follow-on work)

- Building the whisper.cpp and OpenVINO GenAI bindings (they are batch conformers to
  the same API; this prototype proves the two poles: Vosk + sherpa-onnx).
- A cross-engine WER bake-off harness.
- Removing the existing Python `sherpa` coprocess (the new binding coexists under a
  distinct name).
- NPU acceleration (explicitly not a requirement for this work).

## The Common API Contract

Every engine backend implements these verbs, reached through thin `stt::` dispatch
procs. A `handle` is opaque: for `critcl` engines it is the recognizer command; for
`coprocess` engines it is the engine name.

| Verb | Returns | Notes |
|---|---|---|
| `stt::create $engine $model $rate $config` | handle + status JSON | constructs the recognizer |
| `stt::process $handle $chunk` | `{partial: <str>, endpoint: 0\|1}` | `endpoint` is the new field |
| `stt::final $handle` | `{text: <str>}` | finalize utterance, return text, reset decoder for next utterance |
| `stt::reset $handle` | status JSON | discard current utterance state |
| `stt::destroy $handle` | — | teardown |

### Contract rules (how streaming and batch collapse to one interface)

- **Batch engines** (whisper.cpp, OpenVINO GenAI, sherpa-onnx *offline*): `process`
  MUST return `partial:""`, `endpoint:0` and buffer the audio internally. The real
  inference runs in `final`.
- **Streaming engines** (Vosk, sherpa-onnx streaming transducer): `process` returns
  incremental `partial` text and MAY set `endpoint:1` when it self-detects
  end-of-utterance.

### Registry capability flags

Per-engine flags added to `engine_registry` in `src/engine.tcl`, so the app branches
on declared capability rather than engine internals:

- `endpointing: self | external`
- `emits_partials: yes | no`

Existing keys retained: `type` (`critcl` | `coprocess`), `command`, `model_dir`,
`model_config`.

Registered entries after this work:

```
vosk         type=critcl    endpointing=external  emits_partials=yes
sherpa-onnx  type=critcl    endpointing=self      emits_partials=yes
sherpa       type=coprocess endpointing=external  emits_partials=yes   (existing Python, unchanged)
faster-whisper type=coprocess endpointing=external emits_partials=no    (existing Python, unchanged)
```

Note: Vosk is `endpointing=external` because the current binding does not surface
Kaldi's native endpointer (`vosk_recognizer_accept_waveform`'s endpoint return is not
wrapped). Vosk therefore uses the app-side fallback. Exposing Vosk's native endpointer
is possible future work but out of scope here.

## sherpa-onnx critcl binding (`src/sherpa/`)

A critcl package structured after `src/vosk/vosk.tcl`, wrapping
`sherpa-onnx/c-api/c-api.h`, using the **online (streaming) Zipformer transducer**
recognizer — the shape that yields live partials plus native endpoint detection.

### C API surface used

- `SherpaOnnxCreateOnlineRecognizer(config)` — config points at the transducer
  encoder/decoder/joiner ONNX files + tokens, with `enable_endpoint_detection = 1` and
  endpoint rule times.
- `SherpaOnnxCreateOnlineStream(recognizer)`
- `SherpaOnnxOnlineStreamAcceptWaveform(stream, sample_rate, samples, n)` — requires
  **float32** PCM in `[-1, 1]`; the binding converts incoming int16 → float internally
  (same class of conversion as the Silero VAD path; do not pass raw bytes).
- `SherpaOnnxIsOnlineStreamReady` / `SherpaOnnxDecodeOnlineStream` — decode-ready loop.
- `SherpaOnnxGetOnlineStreamResult(recognizer, stream)` → current hypothesis text
  (the `partial`).
- `SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream)` → sets the `endpoint` flag.
- `SherpaOnnxOnlineStreamReset(recognizer, stream)` — called on endpoint and on
  `final`.

### Tcl command surface (mirrors Vosk)

- `sherpa-onnx create_recognizer -rate <hz>` → a handle command supporting:
  - `process <chunk>` → JSON `{partial, endpoint}`
  - `final-result` → JSON `{text}`
  - `reset`
- Namespaced under `::sherpa` (or equivalent) following the Vosk package layout.

### Build

- Makefile modeled on `src/vosk/Makefile`.
- Use `/home/john/bin/critcl` (Tcl 9), consistent with all other packages.
- `critcl::clibraries -L/home/john/pkg/install/lib -ltclstub` (the Tcl 9 stubs fix —
  never `-ltclstub8.6`).
- Link `-lsherpa-onnx-c-api` and its onnxruntime dependency; add sherpa-onnx lib dir to
  the link path and to `LD_LIBRARY_PATH` in the run script as needed.
- Do NOT use `critcl::cproc` with a `Tcl_Obj*` return type (segfaults under Tcl 9);
  follow the established pattern in the other bindings.

### Model

- Streaming Zipformer transducer model, staged under `models/sherpa-onnx/`
  (encoder/decoder/joiner ONNX + tokens). Exact model selection is an implementation
  detail; a standard k2-fsa streaming Zipformer English model is the starting point.

## Processing-loop integration (`src/engine.tcl`)

1. **Capability lookup at init:**
   ```tcl
   set self_endpoint [expr {[get_property $engine_name endpointing] eq "self"}]
   ```

2. **`process_chunk` returns the parsed dict** (currently ~`engine.tcl:424`), so the
   loop sees both `partial` and `endpoint` (today it forwards only `partial`).

3. **Finalization decision** (replacing the energy-only silence check at
   ~`engine.tcl:399-416`):
   - `self_endpoint` engines: call `process_final` when `process` returns
     `endpoint:1`. The recognizer, not the energy timer, gates finalization.
   - `external` engines (whisper.cpp, OpenVINO GenAI, and current-Vosk): finalize via
     app-side endpointing = **partial-stability** ("partial text unchanged for N ms")
     OR the existing energy-silence timer, whichever fires first. Built once here; all
     `external` engines inherit it. `N` is configurable (`partial_stable_ms`, default
     to be chosen during implementation).

4. **Light dispatch cleanup:** introduce `stt::create/process/final/reset/destroy`
   procs that contain the single `if {$engine_type eq "critcl"} … else
   {::coprocess::…}` branch. `engine.tcl` calls only `stt::` verbs; the five inline
   branches (~lines 432, 462, 510, 530, 570) collapse to one. Scope is limited to the
   call sites the endpoint change already visits — no unrelated refactor.

## Testing

- **Binding unit tests** (`src/sherpa/tests/`, mirroring `src/vosk/tests` and the style
  of `src/test_vad_silero.tcl`): feed a known WAV; assert a non-empty transcript and
  that `endpoint` transitions 0 → 1 at utterance end.
- **Contract test** (the "all four meet the API" guarantee): one table-driven test that
  runs the same short WAV through each *available* engine via the `stt::` verbs and
  asserts the return shape — `process` yields keys `{partial, endpoint}`, `final` yields
  a non-empty `{text}`. Engines not yet built are **skipped, not failed**.
- **Partial-stability endpointing** is covered by a focused test that feeds a chunk
  stream with a trailing repeat/silence and asserts finalization fires on stability for
  an `external` engine.

## Risks & Mitigations

- **sherpa-onnx float conversion / sample rate:** wrong scaling or rate yields garbage
  transcripts. Mitigate with the binding unit test on a known WAV before integration.
- **Heavy-noise false partials:** an `external`-path recognizer may decode noise as
  spurious words, keeping the partial changing and delaying the stability endpoint.
  Mitigate by combining partial-stability with the energy-silence timer (OR), and by
  preferring the `self`-endpoint path (sherpa-onnx) where available.
- **Contract drift for batch engines:** whisper.cpp/OpenVINO are not built here; the
  contract test enforces shape for whatever is present so future conformers are checked
  the moment they land.

## Affected Files

- `src/sherpa/` — new critcl package (binding, Makefile, tests).
- `src/engine.tcl` — registry flags, `stt::` dispatch procs, capability-driven
  finalization, `process_chunk` return.
- `src/coprocess.tcl` — unchanged behavior; called through the new `stt::` layer.
- `models/sherpa-onnx/` — staged streaming Zipformer model.
- `CLAUDE.md` / memory — note the new engine and the `stt::` contract.
