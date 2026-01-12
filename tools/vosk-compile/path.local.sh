# Local path.sh for cheeroot-based Kaldi
# Source this instead of path.sh

# Kaldi binaries via cheeroot wrappers
export PATH=/home/cheeroot/bin:$PATH

# SRILM replacements (native Python)
export PATH=$HOME/src/talkie/tools:$PATH

# OpenFST tools (native build)
export PATH=$HOME/src/fst-tools/install/bin:$PATH
export LD_LIBRARY_PATH=$HOME/src/fst-tools/install/lib:$LD_LIBRARY_PATH

# Utils scripts (need perl from cheeroot for some)
export PATH=$PWD/utils:$PWD:$PATH

export LC_ALL=C
