# Building a Custom Vosk lgraph Model

Rebuilds `vosk-model-en-us-0.22-lgraph` with domain vocabulary scraped
from your documents and installs the result under `models/vosk/` in a
date-stamped directory.

## TL;DR

```bash
cd /path/to/talkie
tools/build-custom-vosk.sh              # uses ~/src ~/Documents ~/notes
tools/build-custom-vosk.sh --switch     # also flip talkie to the new model
```

New model lands at `models/vosk/vosk-model-en-us-0.22-lgraph-YYYY-MM-DD/`.
With `--switch`, `~/.config/talkie.conf`'s `vosk_modelfile` is updated to
that name; talkie's config-file watcher picks it up within ~1 s and
hot-swaps the engine live. Re-opening the config dialog also rescans
`models/vosk/` so the new entry appears in the dropdown.

## What it does, end to end

```
┌─ LOCAL (this machine) ────────────────────────────────────────────────┐
│ 1. extract_vocabulary.py scans corpus dirs for .md + .txt files.      │
│    Emits: extra.txt (context sentences), extra.dic (G2P pronunciations) │
│                                                                        │
│ 2. rsync everything the remote build needs into an ephemeral work     │
│    dir on gpu:                                                         │
│      base model: am/, compile/db/, compile/lgraph-base.lm.gz,          │
│                  compile/missing_pronunciations.txt                    │
│      scripts:    compile-lgraph-docker.sh, compile-inner.sh,           │
│                  dict-pruned.py                                        │
│      vocab:      extra.txt, extra.dic                                  │
└────────────────────────────────────────────────────────────────────────┘
┌─ REMOTE (gpu, via ssh) ───────────────────────────────────────────────┐
│ 3. compile-lgraph-docker.sh runs the build inside the kaldi-opengrm    │
│    container as the host uid/gid. All six build steps in one          │
│    docker run:                                                         │
│                                                                        │
│    a. dict-pruned.py → data/dict/lexicon.txt                          │
│         Merges en.dic (filtered to base-LM words), missing             │
│         pronunciations, extra.dic, and G2P for words in extra.txt.    │
│                                                                        │
│    b. prepare_lang.sh → data/lang/ (L.fst, words.txt, phones/ …)      │
│                                                                        │
│    c. Build DOMAIN LM from extra.txt:                                  │
│         farcompilestrings → ngramcount → ngrammake (Witten-Bell)       │
│                                                                        │
│    d. Load BASE LM ARPA into an FST (same symbol space).               │
│                                                                        │
│    e. Interpolate: ngrammerge --method=model_merge --alpha=0.95        │
│       (95% base + 5% domain). Sort → data/Gr.fst.                      │
│                                                                        │
│    f. Build HCLr.fst (olabel_lookahead) via the standard Kaldi         │
│       fstcomposecontext + make-h-transducer + fstconvert pipeline.     │
│                                                                        │
│    Step 5 of the outer script installs build/ → ../graph/.             │
└────────────────────────────────────────────────────────────────────────┘
┌─ LOCAL ───────────────────────────────────────────────────────────────┐
│ 4. Create models/vosk/vosk-model-en-us-0.22-lgraph-YYYY-MM-DD/ with   │
│    local am/, conf/, ivector/ (unchanged across builds) and the fresh │
│    graph/ rsync'd back from gpu. Assert HCLr.fst is olabel_lookahead   │
│    and that 20/20 sampled domain words landed in the new words.txt.   │
│ 5. (--switch) Write new vosk_modelfile into talkie.conf.              │
│ 6. Remove the remote work dir. (--keep-remote to skip.)                │
└────────────────────────────────────────────────────────────────────────┘
```

## Stateless remote

The build host (`gpu` by default) is stateless: it needs only

1. ssh access
2. docker
3. the `kaldi-opengrm:latest` image

Everything else — base model inputs, compile scripts, today's vocabulary
— is rsync'd into `$GPU_WORK_DIR/vosk-build/` per build and cleaned up
at the end. Any machine with those three can become the build host
without setup; swap it with `GPU_HOST=buildbox tools/build-custom-vosk.sh`.

The local repo at `models/vosk/vosk-model-en-us-0.22-lgraph/` is the
single source of truth for the base model and its compile inputs.

## Why interpolate the LM

The base LM (`lgraph-base.lm.gz`) was trained on generic English and has
**none** of our domain words — `vosk`, `openvino`, `kaldi`, `critcl`,
`phonetisaurus`. If we just add them to the lexicon (L.fst) without
giving them LM probabilities, `ngramread --OOV_symbol="[unk]"` buckets
them into `[unk]` and the decoder effectively never picks them.

Step 3c–3e fix this by building a small n-gram LM from the context
sentences in `extra.txt`, then linearly mixing it with the base LM.
α=0.95 (95% base weight, 5% domain) mirrors what SRILM's `-lambda 0.95`
used when `lm-test` was built under the old toolchain.

**Rare-word limit.** A word that appears only a handful of times in
`extra.txt` still gets very little mass after interpolation. If you see
a domain word being decoded as a multi-word phonetic lookalike
("phonetisaurus" → "phone net to soar us"), it's a probability problem,
not a pronunciation one. Options:
- Lower α (e.g. 0.80) to boost the domain LM globally — edit
  `compile-inner.sh`.
- Duplicate the word's contexts 10× in the corpus before rebuilding.
- Hand-write natural sentences containing it and drop them in somewhere
  the extractor will pick up.

## The pieces

### Canonical scripts (in-repo, pushed to gpu on every build)

| Path | Purpose |
|---|---|
| `tools/build-custom-vosk.sh` | Local driver. Extract → stage remote → build → fetch → install → (--switch) flip config → clean remote. |
| `tools/extract_vocabulary.py` | Scan corpus dirs (`.md`, `.txt`, respecting `.gitignore`), filter noise, run G2P. |
| `tools/compile-lgraph-docker.sh` | Runs on gpu. One `docker run --user $(id -u):$(id -g)` against the `kaldi-opengrm` image, then installs `build/` → `graph/`. |
| `tools/compile-inner.sh` | Runs inside the container. All six build steps, in order. |
| `tools/dict-pruned.py` | Generates `lexicon.txt` from `en.dic` + `extra.dic` + `extra.txt` G2P + `missing_pronunciations.txt`. |
| `tools/kaldi-opengrm.Dockerfile` | Rebuilds the remote image if it's ever lost. |

### Local base model (source of truth — in `models/vosk/vosk-model-en-us-0.22-lgraph/`)

| Path | Purpose | Source |
|---|---|---|
| `am/`, `conf/`, `ivector/`, `graph/` | The original Vosk model as shipped. | [`vosk-model-en-us-0.22-lgraph.zip`](https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-lgraph.zip) |
| `compile/db/en.dic` | Base pronunciation dictionary, ~312k entries. | [`vosk-model-en-us-0.22-compile.zip`](https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-compile.zip) |
| `compile/db/en-g2p/en.fst` | Phonetisaurus G2P model. | same compile package |
| `compile/db/phone/*` | Phone-set definitions. | same compile package |
| `compile/lgraph-base.lm.gz` | Base LM ARPA, extracted once from the shipped `Gr.fst`. | derived (see below) |
| `compile/missing_pronunciations.txt` | G2P for LM words not in `en.dic`. | derived (see below) |

### Cold-boot: reconstructing the base model from scratch

If you lose the local tree (or start on a fresh machine), assemble it
from the two upstream zips plus two one-time derivation steps. This
section is the whole recipe — you don't need anything outside it.

```bash
# 1. Download and place the runtime model.
cd /tmp
wget https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-lgraph.zip
unzip vosk-model-en-us-0.22-lgraph.zip -d /path/to/talkie/models/vosk/

# 2. Download the compile package and stage its db/ into compile/.
wget https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-compile.zip
unzip vosk-model-en-us-0.22-compile.zip
cd /path/to/talkie/models/vosk/vosk-model-en-us-0.22-lgraph
mkdir -p compile/db
cp -r /tmp/vosk-model-en-us-0.22-compile/db/en.dic     compile/db/
cp -r /tmp/vosk-model-en-us-0.22-compile/db/en-g2p     compile/db/
cp -r /tmp/vosk-model-en-us-0.22-compile/db/phone      compile/db/

# 3. Extract the base LM ARPA from the shipped Gr.fst. Needs the
#    kaldi-opengrm image — build it from tools/kaldi-opengrm.Dockerfile
#    first (see "Prerequisites" below).
cd compile
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD/..":/model -w /model/compile kaldi-opengrm bash -c '
        export PATH=/opt/miniforge/bin:$PATH
        ngramprint --ARPA ../graph/Gr.fst | gzip > lgraph-base.lm.gz'

# 4. Generate missing_pronunciations.txt — words in the LM but not in
#    en.dic, G2P'd via phonetisaurus. Takes ~1 minute.
python3 <<'PY'
import gzip, phonetisaurus
lm_words = set()
with gzip.open('lgraph-base.lm.gz', 'rt') as f:
    in_unigrams = False
    for line in f:
        s = line.strip()
        if s == '\\1-grams:': in_unigrams = True; continue
        if s.startswith('\\') and s.endswith(':'):
            if in_unigrams: break
            continue
        if in_unigrams and s:
            parts = s.split('\t')
            if len(parts) >= 2 and not parts[1].startswith('<'):
                lm_words.add(parts[1])
dic_words = {line.split()[0].split('(')[0] for line in open('db/en.dic')}
missing = sorted(lm_words - dic_words)
with open('missing_pronunciations.txt', 'w') as out:
    for w, phones in phonetisaurus.predict(missing, 'db/en-g2p/en.fst'):
        out.write(f'{w} {" ".join(phones)}\n')
print(f'wrote {len(missing)} pronunciations')
PY
```

After this, `tools/build-custom-vosk.sh` works as documented above.

### The `kaldi-opengrm` container image

Built from `tools/kaldi-opengrm.Dockerfile`. Layers onto the upstream
`kaldiasr/kaldi:latest`:

- Miniforge at `/opt/miniforge`
- OpenGRM NGram via `mamba install -y ngram` (provides `ngramread`,
  `ngramprint`, `ngramcount`, `ngrammake`, `ngrammerge`,
  `farcompilestrings`, and its own build of OpenFST)
- Phonetisaurus via pip (baked in so the container can run as a
  non-root user at build time)

`compile-inner.sh` puts **Kaldi's** OpenFST first in `PATH` and
`LD_LIBRARY_PATH`. Important: conda's OpenFST is a different build than
Kaldi's `openfst-1.8.4`, and letting it shadow Kaldi's produces FSTs
that Kaldi's `validate_lang.pl` rejects as "not olabel sorted". Miniforge
is only on PATH to supply the `ngram*` tools.

## Prerequisites

### Local
- `rsync`, `ssh`, `jq`, `python3`
- `phonetisaurus` on `PATH` — `pip install --user phonetisaurus`
- ssh alias for the build host (default `gpu`; override with `GPU_HOST=`)

### Remote
- ssh access (same user as local by default)
- docker
- `kaldi-opengrm:latest` image

To build the image on a fresh host:

```bash
scp tools/kaldi-opengrm.Dockerfile gpu:/tmp/kaldi-opengrm.Dockerfile
ssh gpu '
  mkdir -p /tmp/kaldi-opengrm-ctx
  mv /tmp/kaldi-opengrm.Dockerfile /tmp/kaldi-opengrm-ctx/Dockerfile
  cd /tmp/kaldi-opengrm-ctx
  docker build -t kaldi-opengrm .
  rm -rf /tmp/kaldi-opengrm-ctx
'
```

Build takes ~15 min and produces a ~12 GB image.

## Overriding the defaults

```bash
# Different corpus
tools/build-custom-vosk.sh ~/projects ~/wiki

# Different date label (also lets you rebuild yesterday's result into
# yesterday's directory)
tools/build-custom-vosk.sh --date 2026-04-22 ~/src

# Different gpu host
GPU_HOST=buildbox tools/build-custom-vosk.sh

# Different remote work dir (useful when multiple users share a host)
GPU_WORK_DIR='~/tmp/vosk-build' tools/build-custom-vosk.sh

# Keep the remote work dir after the build (debugging)
tools/build-custom-vosk.sh --keep-remote
```

## Troubleshooting

**Model isn't in the config dropdown.** The dropdown list is refreshed
on startup and whenever the config dialog opens (`proc config` calls
`config_refresh_models`). If the running talkie was launched before the
new dir existed, just reopen the dialog — it should now be there.

**Garbage transcription after switching.** Verify the FST type:
```bash
file models/vosk/vosk-model-en-us-0.22-lgraph-YYYY-MM-DD/graph/HCLr.fst
# Should say: fst type: olabel_lookahead
```
If it says `fst type: vector`, the `fstconvert` step failed — check the
tail of `compile-inner.sh` output.

**Domain word is in vocab but not decoded.** LM-mass problem (see
"Rare-word limit" above). Count occurrences in the corpus:
```bash
awk 'NR<=20 {print $1}' /tmp/vosk-vocab-*/extra.dic  # top 20 domain words
# or trigger a build with --keep-remote and inspect extra.txt on gpu
```

**`ModuleNotFoundError: No module named 'phonetisaurus'` inside
container.** The image predates phonetisaurus being baked in. Rebuild
it from the current Dockerfile (see "To build the image" above).

**Build fails in `prepare_lang.sh` with "L.fst is not olabel sorted" or
"reconstructed 0 words".** `compile-inner.sh` writes a `path.sh` stub
before calling prepare_lang.sh; `validate_lang.pl` sources it in every
sub-check. If the stub is missing, those false-negative errors cascade.
Confirm `path.sh` appears in the log.

**Rollback.** Dated builds are kept; point the conf file at an older
one:
```bash
jq --arg m "vosk-model-en-us-0.22-lgraph" '.vosk_modelfile=$m' \
   ~/.config/talkie.conf | sponge ~/.config/talkie.conf
```

## References

- [Vosk LM adaptation](https://alphacephei.com/vosk/adaptation)
- [Kaldi mkgraph_lookahead.sh](https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/utils/mkgraph_lookahead.sh)
- [OpenGRM NGram library](https://www.opengrm.org/twiki/bin/view/GRM/NGramLibrary)
