#!/usr/bin/env python3
"""Build a phoneme recognizer model from an existing Vosk compile package.

This creates a model that outputs phoneme sequences instead of words,
useful for debugging pronunciations and understanding what the acoustic
model actually hears.

IMPORTANT: This script must be run on the GPU host (not locally).
It requires podman with kaldiasr/kaldi image and the Vosk compile package.

Usage:
    # On GPU host:
    scp tools/build-phoneme-model.py gpu:~/vosk-lgraph-compile/
    ssh gpu
    cd ~/vosk-lgraph-compile
    ./build-phoneme-model.py . ~/models/vosk-phoneme --reference-model ~/models/vosk-custom-lgraph

    # Then fetch result:
    scp -r gpu:~/models/vosk-phoneme ~/src/talkie/models/vosk/phoneme

Prerequisites on GPU host:
    - podman with docker.io/kaldiasr/kaldi:latest image
    - ~/vosk-lgraph-compile/ with db/en.dic, exp/chain/tdnn/, utils/
    - Existing Vosk model for --reference-model (provides ivector files)
"""

import argparse
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def run(cmd: str, cwd: Path | None = None, check: bool = True):
    """Run shell command."""
    print(f"  $ {cmd}")
    result = subprocess.run(cmd, shell=True, cwd=cwd)
    if check and result.returncode != 0:
        print(f"ERROR: Command failed with exit code {result.returncode}")
        sys.exit(1)
    return result.returncode


def extract_phonemes(compile_dir: Path) -> list[str]:
    """Extract unique phonemes from the dictionary."""
    dic_path = compile_dir / "db" / "en.dic"
    if not dic_path.exists():
        raise FileNotFoundError(f"Dictionary not found: {dic_path}")

    phonemes = set()
    with open(dic_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                phonemes.update(parts[1:])

    return sorted(phonemes)


def create_words_txt(phonemes: list[str], output_path: Path):
    """Create words.txt mapping phonemes to word IDs."""
    with open(output_path, 'w') as f:
        f.write("<eps> 0\n")
        word_id = 1
        for phone in phonemes:
            f.write(f"{phone} {word_id}\n")
            word_id += 1
        # Add sentence boundary symbols (required for ARPA LM)
        f.write(f"<s> {word_id}\n")
        word_id += 1
        f.write(f"</s> {word_id}\n")
        word_id += 1
        # Add disambiguation symbol for LM
        f.write(f"#0 {word_id}\n")


def create_phoneme_lm(phonemes: list[str], output_path: Path):
    """Create simple unigram ARPA language model with sentence markers."""
    n = len(phonemes) + 2  # +2 for <s> and </s>
    log_prob = math.log10(1.0 / n)

    with open(output_path, 'w') as f:
        f.write("\\data\\\n")
        f.write(f"ngram 1={n}\n\n")
        f.write("\\1-grams:\n")
        # Sentence boundary symbols (required by Kaldi)
        f.write(f"{log_prob:.4f} <s>\n")
        f.write(f"{log_prob:.4f} </s>\n")
        for phone in phonemes:
            f.write(f"{log_prob:.4f} {phone}\n")
        f.write("\n\\end\\\n")


def create_lexicon_fst_txt(phonemes: list[str], phones_txt: Path, output_path: Path):
    """Create lexicon FST in text format.

    For phoneme model: each phoneme word maps to itself.
    FST format: src dest ilabel olabel [weight]
    Uses symbol names, not IDs (fstcompile will look up IDs from symbol tables).

    Important: Phones have position markers (_B, _E, _I, _S) for word position.
    We need to map ALL variants to the base phoneme output so continuous
    speech is recognized regardless of phone position.
    """
    # Read phones.txt to check which phones exist
    available_phones = set()
    with open(phones_txt) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                available_phones.add(parts[0])

    with open(output_path, 'w') as f:
        for phone in phonemes:
            # Map ALL position variants to the same output phoneme
            # _B = beginning, _I = inside, _E = end, _S = singleton
            found_any = False

            # Try base phone first (for phones without position markers like SIL, SPN)
            if phone in available_phones:
                f.write(f"0 0 {phone} {phone}\n")
                found_any = True

            # Try all position variants
            for suffix in ['_B', '_I', '_E', '_S']:
                phone_variant = f"{phone}{suffix}"
                if phone_variant in available_phones:
                    f.write(f"0 0 {phone_variant} {phone}\n")
                    found_any = True

            if not found_any:
                print(f"Warning: phone {phone} not found in phones.txt, skipping")

        # Final state
        f.write("0\n")


def run_in_kaldi_container(compile_dir: Path, work_dir: Path, script: str):
    """Run a script inside the Kaldi container."""
    cmd = (
        f"podman run --rm "
        f"-v {work_dir}:/work "
        f"-v {compile_dir}:/compile:ro "
        f"-w /work "
        f"docker.io/kaldiasr/kaldi:latest "
        f"bash -c '{script}'"
    )
    run(cmd)


def build_graph(compile_dir: Path, work_dir: Path, phonemes: list[str]):
    """Build FST graph using Kaldi tools in container."""
    # Copy necessary files from compile package
    shutil.copytree(compile_dir / "utils", work_dir / "utils", dirs_exist_ok=True)

    # Copy existing lang directory structure
    lang_src = compile_dir / "data" / "lang"
    lang_dst = work_dir / "data" / "lang"
    lang_dst.mkdir(parents=True)

    # Copy phones directory and other files we need
    shutil.copytree(lang_src / "phones", lang_dst / "phones")
    shutil.copy(lang_src / "phones.txt", lang_dst)
    shutil.copy(lang_src / "topo", lang_dst)

    # Create our phoneme-specific files
    create_words_txt(phonemes, lang_dst / "words.txt")

    # Create lexicon FST text file
    create_lexicon_fst_txt(phonemes, lang_dst / "phones.txt", work_dir / "L.txt")

    # Create OOV file (use first silence phone)
    with open(lang_dst / "oov.txt", 'w') as f:
        f.write("SIL\n")
    with open(lang_dst / "oov.int", 'w') as f:
        # Find SIL word ID
        with open(lang_dst / "words.txt") as wf:
            for line in wf:
                parts = line.strip().split()
                if parts[0] == "SIL":
                    f.write(f"{parts[1]}\n")
                    break

    # Build FSTs in container
    kaldi_script = """
set -e
export PATH=/opt/kaldi/tools/openfst-1.8.4/bin:/opt/kaldi/src/fstbin:/opt/kaldi/src/lmbin:/opt/kaldi/src/bin:/work/utils:$PATH
export LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/src/lib:$LD_LIBRARY_PATH
export LC_ALL=C

echo "Building L.fst from text..."
fstcompile --isymbols=data/lang/phones.txt --osymbols=data/lang/words.txt L.txt | \\
    fstarcsort --sort_type=olabel > data/lang/L.fst

# Create L_disambig.fst (same as L.fst for this simple case)
cp data/lang/L.fst data/lang/L_disambig.fst

echo "Building G.fst from ARPA..."
gzip -c phoneme.arpa > phoneme.arpa.gz
gunzip -c phoneme.arpa.gz | arpa2fst --disambig-symbol='#0' --read-symbol-table=data/lang/words.txt - | \\
    fstarcsort --sort_type=ilabel > data/lang/G.fst

echo "Building HCLG graph..."
echo "=== mkgraph.sh output ==="
utils/mkgraph.sh --self-loop-scale 1.0 data/lang /compile/exp/chain/tdnn graph 2>&1 | tee mkgraph.log
MKGRAPH_EXIT=${PIPESTATUS[0]}
echo "=== mkgraph.sh exit code: $MKGRAPH_EXIT ==="

if [ ! -f graph/HCLG.fst ]; then
    echo ""
    echo "ERROR: mkgraph.sh failed to create HCLG.fst"
    echo "Check mkgraph.log for details"
    echo ""
    echo "=== Last 50 lines of mkgraph.log ==="
    tail -50 mkgraph.log
    echo ""
    echo "=== Checking required files ==="
    echo "L.fst exists: $(test -f data/lang/L.fst && echo yes || echo NO)"
    echo "G.fst exists: $(test -f data/lang/G.fst && echo yes || echo NO)"
    echo "words.txt exists: $(test -f data/lang/words.txt && echo yes || echo NO)"
    echo "phones.txt exists: $(test -f data/lang/phones.txt && echo yes || echo NO)"
    echo "phones/ dir exists: $(test -d data/lang/phones && echo yes || echo NO)"
    ls -la data/lang/
    echo ""
    echo "=== Contents of data/lang/phones/ ==="
    ls -la data/lang/phones/ 2>/dev/null || echo "phones/ directory missing"
    exit 1
fi

echo "Graph files:"
ls -la graph/
"""
    run_in_kaldi_container(compile_dir, work_dir, kaldi_script)


def assemble_model(compile_dir: Path, work_dir: Path, output_dir: Path,
                   reference_model: Path | None = None):
    """Assemble final model directory."""
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    # Create subdirectories
    (output_dir / "am").mkdir()
    (output_dir / "conf").mkdir()
    (output_dir / "ivector").mkdir()
    (output_dir / "graph").mkdir()

    # Copy acoustic model
    tdnn_dir = compile_dir / "exp" / "chain" / "tdnn"
    shutil.copy(tdnn_dir / "final.mdl", output_dir / "am")
    shutil.copy(tdnn_dir / "tree", output_dir / "am")

    # Copy ivector extractor - try multiple sources
    ivector_src = None
    ivector_candidates = [
        tdnn_dir / "ivector_extractor",
        compile_dir / "exp" / "nnet3_chain" / "extractor",
        compile_dir / "ivector",
    ]
    if reference_model:
        ivector_candidates.insert(0, reference_model / "ivector")

    for candidate in ivector_candidates:
        if candidate.exists() and (candidate / "final.ie").exists():
            ivector_src = candidate
            print(f"Using ivector from: {ivector_src}")
            break

    if ivector_src:
        for f in ivector_src.iterdir():
            if f.is_file():
                shutil.copy(f, output_dir / "ivector")
    else:
        print("WARNING: No ivector extractor found! Model may not work.")
        print("Use --reference-model to specify a working model to copy ivector from.")

    # Copy graph files
    graph_src = work_dir / "graph"
    for pattern in ["*.fst", "words.txt", "phones.txt", "disambig_tid.int"]:
        for f in graph_src.glob(pattern):
            if f.is_file():
                shutil.copy(f, output_dir / "graph")

    # Also copy words.txt from lang if not in graph
    if not (output_dir / "graph" / "words.txt").exists():
        shutil.copy(work_dir / "data" / "lang" / "words.txt", output_dir / "graph")

    if (graph_src / "phones").exists():
        shutil.copytree(graph_src / "phones", output_dir / "graph" / "phones")

    # Create config files
    with open(output_dir / "conf" / "mfcc.conf", 'w') as f:
        f.write("""--sample-frequency=16000
--use-energy=false
--num-mel-bins=40
--num-ceps=40
--low-freq=20
--high-freq=7600
--allow-upsample=true
--allow-downsample=true
""")

    with open(output_dir / "conf" / "model.conf", 'w') as f:
        f.write("""--min-active=200
--max-active=7000
--beam=13.0
--lattice-beam=6.0
--acoustic-scale=1.0
--frame-subsampling-factor=3
--endpoint.silence-phones=1:2:3:4:5:6:7:8:9:10:11:12:13:14:15
--endpoint.rule2.min-trailing-silence=0.5
--endpoint.rule3.min-trailing-silence=1.0
--endpoint.rule4.min-trailing-silence=2.0
""")

    with open(output_dir / "ivector" / "splice.conf", 'w') as f:
        f.write("--left-context=3\n--right-context=3\n")


def main():
    parser = argparse.ArgumentParser(
        description="Build phoneme recognizer model from Vosk compile package"
    )
    parser.add_argument("compile_dir", type=Path,
                        help="Path to vosk compile directory (with db/, exp/)")
    parser.add_argument("output_dir", type=Path,
                        help="Path for output phoneme model")
    parser.add_argument("--keep-work", action="store_true",
                        help="Keep temporary working directory")
    parser.add_argument("--reference-model", type=Path,
                        help="Copy ivector files from this existing model")

    args = parser.parse_args()

    if not args.compile_dir.exists():
        print(f"ERROR: Compile directory not found: {args.compile_dir}")
        sys.exit(1)

    if not (args.compile_dir / "db" / "en.dic").exists():
        print(f"ERROR: Dictionary not found: {args.compile_dir}/db/en.dic")
        sys.exit(1)

    # Check for podman
    if shutil.which("podman") is None:
        print("ERROR: podman not found")
        sys.exit(1)

    # Create working directory
    work_dir = Path(tempfile.mkdtemp(prefix="phoneme-model-"))
    print(f"Working directory: {work_dir}")

    try:
        # Step 1: Extract phonemes
        print("\n=== Step 1: Extracting phoneme inventory ===")
        phonemes = extract_phonemes(args.compile_dir)
        print(f"Found {len(phonemes)} phonemes")

        # Step 2: Create phoneme LM
        print("\n=== Step 2: Creating phoneme language model ===")
        create_phoneme_lm(phonemes, work_dir / "phoneme.arpa")

        # Step 3: Build FST graph
        print("\n=== Step 3: Building FST graph (in container) ===")
        build_graph(args.compile_dir, work_dir, phonemes)

        # Step 4: Assemble model
        print("\n=== Step 4: Assembling output model ===")
        assemble_model(args.compile_dir, work_dir, args.output_dir,
                       args.reference_model)

        # Report
        print("\n=== Build Complete ===")
        print(f"Phoneme model: {args.output_dir}")
        total_size = sum(f.stat().st_size for f in args.output_dir.rglob("*") if f.is_file())
        print(f"Total size: {total_size / 1024 / 1024:.1f} MB")

    finally:
        if not args.keep_work:
            shutil.rmtree(work_dir, ignore_errors=True)
        else:
            print(f"\nWork directory kept: {work_dir}")


if __name__ == "__main__":
    main()
