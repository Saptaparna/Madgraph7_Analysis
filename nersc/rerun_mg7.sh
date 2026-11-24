#!/bin/bash
# Repeat the 10M-event pp->jj validation with a newer MadGraph7 install, against the existing
# MG5 reference (and the previous MG7 sample, if still there).
#
#   bash rerun_mg7.sh <account> <label> [nevents]
#   e.g. bash rerun_mg7.sh <account> nov23 10000000
#
# <label> is the MG7_LABEL used with setup_mg7.sh (env file $MG7_BASE/env_mg7_<label>.sh).
# Output: $MG7_BASE/runs_<nevents>_<label>/  (logs/, LHE, cmp_*.pdf, cmp.txt)
#
# Reference samples are taken from $MG7_BASE/runs_<nevents>/ (the September run). Perlmutter
# purges scratch files not accessed for 8 weeks: if the MG5 (LHAPDF) reference is gone, it is
# regenerated here (MG5 is unchanged), and the comparison waits for it.
set -euo pipefail
ACCOUNT=${1:?usage: rerun_mg7.sh <account> <label> [nevents]}
LABEL=${2:?usage: rerun_mg7.sh <account> <label> [nevents]}
NEV=${3:-10000000}
PT=${PTJ:-100}
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${MG7_BASE:-$PSCRATCH/mg7_athena}
ENV=$BASE/env_mg7_$LABEL.sh
[ -f "$ENV" ] || { echo "no $ENV: run MG7_TAG=<commit> MG7_LABEL=$LABEL bash setup_mg7.sh first"; exit 1; }
source "$ENV"
WORK=$BASE/runs_${NEV}_$LABEL
REF=$BASE/runs_$NEV
mkdir -p "$WORK/logs"
COMMON="-A $ACCOUNT -o $WORK/logs/%x-%j.out"

# record exactly which MG7 is being validated
( cd "$MG7_DIR" && git log -1 --format='MG7 commit %H (%cd)' && cat VERSION ) | tee "$WORK/mg7_version.txt"

J1=$(sbatch --parsable $COMMON -J mg7-$LABEL -C gpu -q shared -N 1 --gpus 1 -c 32 -t 02:00:00 \
     --export=ALL,WORK=$WORK,NEVENTS=$NEV,GRIDPACK=False \
     --wrap "source $ENV; DEVICE=cuda bash $HERE/run_dijet.sh mg7")
DEPS=$J1

MG5REF=$REF/dijet_mg5_pt${PT}_lhapdf.lhe.gz
if [ -s "$MG5REF" ] && zcat "$MG5REF" 2>/dev/null | tail -c 200 | grep -q "</LesHouchesEvents>"; then
  echo "MG5 reference found: $MG5REF"
  ln -sf "$MG5REF" "$WORK/ref_mg5_lhapdf.lhe.gz"
else
  echo "MG5 reference missing (purged?): regenerating it in $WORK"
  command -v lhapdf-config >/dev/null || { echo "install LHAPDF first: conda install -y -c conda-forge lhapdf"; exit 1; }
  J2=$(sbatch --parsable $COMMON -J mg5lha-$LABEL -C cpu -q regular -N 1 -t 02:00:00 \
       --export=ALL,WORK=$WORK,NEVENTS=$NEV \
       --wrap "source $ENV; PDF_MODE=lhapdf bash $HERE/run_dijet.sh mg5 && ln -sf $WORK/dijet_mg5_pt${PT}_lhapdf.lhe.gz $WORK/ref_mg5_lhapdf.lhe.gz")
  DEPS=$DEPS:$J2
fi

FILES="ref_mg5_lhapdf.lhe.gz"; LABELS="MG5-LHAPDF"
OLDMG7=$REF/dijet_mg7_pt${PT}.lhe.gz
if [ -s "$OLDMG7" ]; then
  ln -sf "$(readlink -f "$OLDMG7")" "$WORK/old_mg7.lhe.gz"
  FILES="$FILES old_mg7.lhe.gz"; LABELS="$LABELS MG7-0.2.1"
else
  echo "previous MG7 sample not found (purged?): comparing against MG5 only"
fi
FILES="$FILES dijet_mg7_pt${PT}.lhe.gz"; LABELS="$LABELS MG7-$LABEL"

J3=$(sbatch --parsable $COMMON -J cmp-$LABEL -C cpu -q shared -n 1 -c 4 -t 01:00:00 \
     --dependency=afterok:$DEPS \
     --wrap "source $ENV; cd $WORK; python $HERE/compare_lhe.py $FILES --labels $LABELS --out cmp_dijet_pt${PT} > cmp.txt")

echo "submitted: MG7 $J1 ${J2:+| MG5-LHAPDF $J2 }| compare $J3"
echo "results:   $WORK/cmp.txt and $WORK/cmp_dijet_pt${PT}_*.pdf"
