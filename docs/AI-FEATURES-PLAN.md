# AI Features Plan

## Background

Talkie's AI/ML stack was built in three layers:

1. **Speech recognition engines** — Vosk (critcl), Sherpa-ONNX (critcl + coprocess), Faster-Whisper (coprocess)
2. **GEC pipeline** — Homophone correction (ELECTRA), Punctuation/Capitalization (DistilBERT), Grammar (T5)
3. **VAD** — Fixed energy threshold in the processing worker

In practice, **Vosk won on every metric**: faster, more accurate, lower latency, no Python dependency.
The GEC pipeline had one critical flaw: the T5 grammar stage is seq2seq generative and would reorder
utterances, converting questions into statements. The punctcap stage likely compounded this by assigning
period (`.`) to the final word of questions instead of question mark (`?`).

---

## Current Status by Component

| Component | Status | Issue |
|-----------|--------|-------|
| Vosk STT | ✓ Production | None |
| Energy threshold VAD | ✓ Production | Misses soft speech, false triggers on noise |
| ELECTRA homophone | Disabled | Architecturally sound; needs audit of homophones.json |
| DistilBERT punctcap | Disabled | Model accuracy issue on questions (`.` vs `?`) |
| T5 grammar (CTranslate2) | Disabled | Generative rewrite — structurally incompatible with dictation |
| Sherpa-ONNX engine | Dead code | Slower and less accurate than Vosk |
| Faster-Whisper engine | Dead code | Slower and less accurate than Vosk |

---

## Plan

### Task 1 — Add Silero VAD (replaces energy threshold)

**Priority:** High
**Risk:** None (additive; energy threshold kept as fallback)

#### What is Silero VAD?

[Silero VAD v4](https://github.com/snakers4/silero-vad) is a ~1MB stateful LSTM ONNX model trained
specifically for voice activity detection. It takes 512-sample float32 windows (32ms at 16kHz) and
returns a speech probability (0–1). It dramatically outperforms energy threshold in:

- Noisy environments (HVAC, keyboard, traffic)
- Soft or distant speech
- Fast onset detection
- Resistance to tonal noise (music, TV)

#### ONNX Model Inputs/Outputs

Silero VAD v4 is stateful — the LSTM h/c state is passed through across calls:

| Tensor | Shape | Type | Description |
|--------|-------|------|-------------|
| `input` | `[1, 512]` | float32 | Audio samples normalized to [-1.0, 1.0] |
| `sr` | scalar | int64 | Sample rate (16000) |
| `h` | `[2, 1, 64]` | float32 | LSTM hidden state (zero-init, then carried forward) |
| `c` | `[2, 1, 64]` | float32 | LSTM cell state (zero-init, then carried forward) |
| → `output` | `[1, 1]` | float32 | Speech probability |
| → `hn` | `[2, 1, 64]` | float32 | New hidden state |
| → `cn` | `[2, 1, 64]` | float32 | New cell state |

#### Infrastructure

`gec::load_model`, `create_request`, `infer`, and `get_output` can all be reused as-is.

**One gap:** `set_input` in `gec.tcl` is hardcoded to create `I64` tensors (designed for BERT token
IDs). Silero VAD needs `F32` tensors for audio data and the LSTM h/c state tensors. A new
`set_input_f32` subcommand (or a typed variant `set_input <index> <data> <type>`) must be added to
the critcl C code before Silero can be wired in. This is a small, well-contained change (~30 lines
of C) but it is a hard prerequisite for Task 1c.

#### NPU Consideration

**Short answer: offer NPU as an option, default to CPU.**

The existing GEC pipeline (punctcap, homophone) runs on NPU because those models fire *once per
utterance* — latency of 8–50ms is fine. Silero VAD fires at **40Hz** (every 25ms during audio
capture). At that cadence, NPU round-trip dispatch overhead (~2–5ms per call on Meteor Lake) is a
significant fraction of the budget, but the inference itself is ~1ms.

In practice this should work fine on NPU — 5ms dispatch + 1ms inference = 6ms total, well within the
25ms window. But:

- The NPU is also running punctcap/homophone at utterance boundaries — concurrent use needs testing.
- CPU inference for such a small model is ~0.5ms — effectively free.
- NPU compilation at startup adds a few hundred ms (acceptable).

**Decision:** Add `vad_device` config key (`"CPU"` default, `"NPU"` available). Use `gec::devices` to
check availability at init time. If `vad_device = "NPU"` but NPU is not available, fall back to CPU
with a warning.

#### Config Changes

Add to `config.tcl` defaults:

```tcl
vad_engine    threshold   ;# "threshold" or "silero"
vad_device    CPU         ;# "CPU" or "NPU" (silero only)
vad_threshold 0.5         ;# speech probability threshold (silero only)
```

The existing `audio_threshold` key continues to control the energy threshold when `vad_engine = threshold`.

#### Implementation Sketch

New file: `src/vad_silero.tcl` — loaded in the processing worker when `vad_engine = silero`.

```tcl
namespace eval ::vad::silero {
    variable model ""
    variable request ""
    variable h {}        ;# LSTM hidden state [2*1*64 floats, zeroed]
    variable c {}        ;# LSTM cell state   [2*1*64 floats, zeroed]
    variable initialized 0

    proc init {model_path device} { ... }
    proc is_speech {audio_data} { ... }  ;# returns 0/1
    proc reset {} { ... }                ;# zero h/c state at utterance boundaries
    proc cleanup {} { ... }
}
```

`is_speech` in `engine.tcl` becomes a dispatch:

```tcl
if {$config(vad_engine) eq "silero"} {
    set prob [::vad::silero::is_speech $data]
    set raw_is_speech [expr {$prob > $config(vad_threshold)}]
} else {
    set raw_is_speech [expr {$audiolevel > $config(audio_threshold)}]
}
```

Audio normalization: the existing `audio::energy` critcl package operates on int16 PCM. Silero needs
float32 normalized to [-1.0, 1.0]. Add a `audio::to_float` command to `src/audio/` (simple C loop:
`sample / 32768.0`).

Model location: `models/vad/silero_vad.onnx`

#### UI Changes

Add to the config dialog (ui-layout.tcl):
- VAD engine selector (dropdown: `threshold` / `silero`)
- VAD device selector (dropdown: `CPU` / `NPU`, enabled only when silero selected)
- Silero threshold slider (0.0–1.0, default 0.5, enabled only when silero selected)

---

### Task 2 — Fix punctcap: question mark heuristic

**Priority:** Medium
**Risk:** None (post-processing only, doesn't change model)

After punctcap runs, apply a heuristic: if the utterance's first word is an interrogative
(`did`, `does`, `do`, `is`, `are`, `was`, `were`, `can`, `could`, `would`, `will`, `shall`,
`should`, `who`, `what`, `when`, `where`, `why`, `how`) **and** the result ends with `.`, replace
the trailing `.` with `?`.

Add to `src/gec/punctcap.tcl` as a post-pass in `restore`. No config needed — this is always correct.

---

### Task 3 — Re-enable homophone correction

**Priority:** Medium
**Risk:** Low

ELECTRA homophone correction cannot reorder sentences — it only substitutes words within a fixed
homophone group. Re-enable with a tightened default scope:

1. Audit `data/homophones.json` — remove groups where the alternatives are rarely confused in
   dictation context (e.g., unusual proper nouns).
2. Re-enable `gec_homophone = 1` as default.
3. Monitor via `~/.config/talkie/feedback.jsonl` (gec events show before/after).

---

### Task 4 — Remove dead code

**Priority:** Low
**Risk:** None

Remove or archive:
- `src/gec/ct2.tcl` — CTranslate2 T5 grammar bindings
- `src/gec/grammar.tcl` — T5 grammar correction module
- `gec_grammar` config key and all references
- `src/sherpa-onnx/` — critcl bindings (coprocess wrapper in `src/engines/` sufficient if ever needed)
- `sherpa` and `faster-whisper` engine entries from `engine_registry` if we want to fully commit to Vosk-only

---

## Implementation Order

```
Task 1a  Download silero_vad.onnx → models/vad/
Task 1b  Add set_input_f32 to gec.tcl critcl C code (prerequisite for 1c)
Task 1c  Add audio::to_float to src/audio/ critcl package
Task 1d  Write src/vad_silero.tcl (init, is_speech, reset, cleanup)
Task 1e  Wire into engine.tcl processing worker (dispatch in is_speech)
Task 1f  Add config keys (vad_engine, vad_device, vad_threshold)
Task 1g  Add UI controls in ui-layout.tcl
Task 2   Add question mark heuristic to punctcap::restore
Task 3   Audit homophones.json, re-enable gec_homophone default
Task 4   Remove dead code
```

---

## Open Questions

- Does Silero VAD v4 ONNX work with OpenVINO's NPU backend without graph compilation errors?
  (Test with `gec::load_model -path silero_vad.onnx -device NPU` before committing to UI option.)
- Should `vad_device` auto-select NPU when available, or always require explicit opt-in?
  Recommendation: explicit opt-in (user sets `vad_device = NPU`) — avoids surprise at startup.
