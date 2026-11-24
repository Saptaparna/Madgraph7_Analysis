#!/bin/bash
# One-time setup of MadGraph7 (+ madspace with CUDA) and MG5_aMC on Perlmutter.
#
#   bash setup_mg7.sh            # run on a login node (the madspace build takes a while;
#                                # use -j to taste, or run it inside an interactive GPU job)
#
# Everything goes under $MG7_BASE (default: $PSCRATCH/mg7_athena). Source env_mg7.sh
# afterwards (it is written by this script) before running anything.
set -euo pipefail

MG7_BASE=${MG7_BASE:-$PSCRATCH/mg7_athena}
MG7_TAG=${MG7_TAG:-main}          # tag, branch or commit to check out
MG7_LABEL=${MG7_LABEL:-}          # e.g. nov23: installs into MadGraph7_nov23 with env_mg7_nov23.sh,
                                  # next to (not over) an existing install
MG7_SRC=MadGraph7${MG7_LABEL:+_$MG7_LABEL}
ENV_FILE=env_mg7${MG7_LABEL:+_$MG7_LABEL}.sh
MG5_REF=${MG5_REF:-}              # e.g. a tag matching the MG5 version ATLAS uses; empty = default branch
CUDA_ARCH=${CUDA_ARCH:-80}        # Perlmutter A100 = sm_80
JOBS=${JOBS:-16}

mkdir -p "$MG7_BASE"
cd "$MG7_BASE"

# --- environment ------------------------------------------------------------
module load PrgEnv-gnu
module load cudatoolkit
module load conda

# MG7 needs python >= 3.12; make a private env instead of relying on the system python
if [ ! -d "$MG7_BASE/pyenv" ]; then
  conda create -y -p "$MG7_BASE/pyenv" python=3.12 cmake numpy matplotlib
fi
conda activate "$MG7_BASE/pyenv"
python --version

# --- MadGraph7 --------------------------------------------------------------
if [ ! -d "$MG7_SRC" ]; then
  git clone https://github.com/MadGraphTeam/MadGraph7.git "$MG7_SRC"
fi
( cd "$MG7_SRC" && git fetch --tags origin && git checkout "$MG7_TAG" && git log -1 --format='commit %h (%cd)' && cat VERSION )

# madspace: CPU (SIMD) + CUDA backends, installed into MadGraph7/madspace/install
# (a git checkout always builds from source; the PyPI wheel is only used by release tarballs)
( cd "$MG7_SRC" && python madspace/install.py --source -y --cuda --cuda-arch "$CUDA_ARCH" \
      --simd --no-hip --no-docs --no-debug -j "$JOBS" )

# --- MG5_aMC reference -------------------------------------------------------
if [ ! -d mg5amcnlo ]; then
  git clone https://github.com/mg5amcnlo/mg5amcnlo.git
fi
if [ -n "$MG5_REF" ]; then ( cd mg5amcnlo && git checkout "$MG5_REF" ); fi
cat mg5amcnlo/VERSION

# --- PDFs --------------------------------------------------------------------
# MG7 reads LHAPDF grids directly (no LHAPDF library needed). Prefer the CVMFS copy;
# otherwise fetch the one set we need.
PDFSET=NNPDF23_lo_as_0130_qed
if [ -d /cvmfs/sft.cern.ch/lcg/external/lhapdfsets/current/$PDFSET ]; then
  PDFPATH=/cvmfs/sft.cern.ch/lcg/external/lhapdfsets/current
else
  PDFPATH=$MG7_BASE/lhapdfsets
  mkdir -p "$PDFPATH"
  ( cd "$PDFPATH" && curl -sSfL https://lhapdfsets.web.cern.ch/current/$PDFSET.tar.gz | tar xz )
fi

# --- env file -----------------------------------------------------------------
cat > "$MG7_BASE/$ENV_FILE" <<EOF
module load PrgEnv-gnu cudatoolkit conda
conda activate $MG7_BASE/pyenv
export MG7_BASE=$MG7_BASE
export MG7_DIR=$MG7_BASE/$MG7_SRC
export MG7_LABEL=$MG7_LABEL
export MG5_DIR=$MG7_BASE/mg5amcnlo
export LHAPDF_DATA_PATH=$PDFPATH
EOF
echo "Done. Next: source $MG7_BASE/$ENV_FILE"
