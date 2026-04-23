# kaldi-opengrm: Kaldi + OpenGRM NGram + phonetisaurus
#
# Builds the image used by compile-lgraph-docker.sh on the gpu host. The
# upstream kaldiasr/kaldi image provides OpenFST (fstarcsort, etc.) and
# Kaldi's fstbin/ but not OpenGRM (ngramread/ngramprint), which we need
# for the Gr.fst build step.
#
# Build:
#   docker build -t kaldi-opengrm -f kaldi-opengrm.Dockerfile .
#
# The image is ~11.8 GB (Kaldi base is ~11.3 GB). phonetisaurus is
# pip-installed at container start by compile-inner.sh, not baked in.

FROM docker.io/kaldiasr/kaldi:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends wget \
 && wget -q https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh \
 && bash /tmp/miniforge.sh -b -p /opt/miniforge \
 && rm /tmp/miniforge.sh \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ENV PATH=/opt/miniforge/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN mamba install -y ngram && conda clean -afy

RUN pip install --no-cache-dir phonetisaurus

ENV LD_LIBRARY_PATH=/opt/kaldi/tools/openfst-1.8.4/lib:/opt/kaldi/tools/openfst-1.8.4/lib/fst:/opt/miniforge/lib:
