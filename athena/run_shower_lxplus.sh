#!/bin/bash
# Local Gen_tf test of the split workflow on lxplus (same release as the Pepper validation).
#
#   bash run_shower_lxplus.sh <path/to/mcjoboptions/999xxx/999999> <mg7_jj_pT100._00001.tar.gz> [nevents]
#
# Run it in a fresh shell (it calls setupATLAS/asetup).
set -eo pipefail
JODIR=$(readlink -f "${1:?directory with the jO (DSID dir)}")
LHETGZ=$(readlink -f "${2:?LHE tarball from package_lhe.sh}")
NEV=${3:-1000}
RELEASE=${RELEASE:-AthGeneration,23.6.68}
ECM=${ECM:-13600}   # must match the beam energy the LHE was generated with

export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh -q
WORKDIR=${WORKDIR:-$PWD/gentf_mg7_$(date +%Y%m%d_%H%M)}
mkdir -p "$WORKDIR" && cd "$WORKDIR"
asetup $RELEASE

Gen_tf.py --ecmEnergy=$ECM \
          --jobConfig="$JODIR" \
          --inputGeneratorFile="$LHETGZ" \
          --outputEVNTFile=EVNT.root \
          --maxEvents=$NEV \
          --randomSeed=1234 2>&1 | tee gentf.log

# things worth checking in the log for MG7 input
echo "=== cross section / efficiency reported by the job"
grep -E "MetaData: (cross-section|GenFiltEff)|sigmaGen|Total events" log.generate 2>/dev/null | tail -5 || true
echo "=== LHE weights seen by Pythia8_i"
grep -iE "weight names|MUR=|MUF=" log.generate 2>/dev/null | head -15 || true
