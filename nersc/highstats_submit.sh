#!/bin/bash
# Submit a high-statistics comparison (default 10M events per sample) as four Slurm jobs:
#   1. MG7 engine on one GPU                      (shared GPU queue)
#   2. MG5_aMC, built-in nn23lo1 PDF               (one full CPU node, multi_run 10 x 1M)
#   3. MG5_aMC, same LHAPDF set as MG7 (alpha_s test)  (one full CPU node)
#   4. comparison, starts when 1-3 have all succeeded
#
#   bash highstats_submit.sh <account> [nevents]
#   e.g. bash highstats_submit.sh <account> 10000000
#
# Output: $MG7_BASE/runs_<N>/ (LHE files, cmp_*.pdf, cmp.txt). About 1 GB (MG5) and 2 GB (MG7) of
# gzipped LHE per 10M events. MG7 legacy mode is left out: it reproduced MG5 to 0.01 %.
set -euo pipefail
ACCOUNT=${1:?usage: highstats_submit.sh <account> [nevents]}
NEV=${2:-10000000}
HERE=$(cd "$(dirname "$0")" && pwd)
source "${MG7_BASE:-$PSCRATCH/mg7_athena}/env_mg7.sh"
WORK=$MG7_BASE/runs_$NEV
mkdir -p "$WORK/logs"
command -v lhapdf-config >/dev/null || { echo "install LHAPDF first: conda install -y -c conda-forge lhapdf"; exit 1; }

COMMON="--export=ALL,WORK=$WORK,NEVENTS=$NEV,GRIDPACK=False -A $ACCOUNT -o $WORK/logs/%x-%j.out"

J1=$(sbatch --parsable $COMMON -J mg7-10M  -C gpu -q shared -N 1 --gpus 1 -c 32 -t 04:00:00 \
     --wrap "source $MG7_BASE/env_mg7.sh; DEVICE=cuda bash $HERE/run_dijet.sh mg7")
J2=$(sbatch --parsable $COMMON -J mg5-10M  -C cpu -q regular -N 1 -t 10:00:00 \
     --wrap "source $MG7_BASE/env_mg7.sh; bash $HERE/run_dijet.sh mg5")
J3=$(sbatch --parsable $COMMON -J mg5lha-10M -C cpu -q regular -N 1 -t 10:00:00 \
     --wrap "source $MG7_BASE/env_mg7.sh; PDF_MODE=lhapdf bash $HERE/run_dijet.sh mg5")
PT=${PTJ:-100}
J4=$(sbatch --parsable $COMMON -J cmp-10M -C cpu -q shared -n 1 -c 4 -t 01:00:00 \
     --dependency=afterok:$J1:$J2:$J3 \
     --wrap "source $MG7_BASE/env_mg7.sh; cd $WORK; python $HERE/compare_lhe.py \
             dijet_mg5_pt${PT}.lhe.gz dijet_mg5_pt${PT}_lhapdf.lhe.gz dijet_mg7_pt${PT}.lhe.gz \
             --labels MG5-nn23lo1 MG5-LHAPDF MG7 --out cmp_dijet_pt${PT} | tee cmp.txt")

echo "submitted: MG7 $J1 | MG5 $J2 | MG5-LHAPDF $J3 | compare $J4 (runs after the other three)"
echo "logs:      $WORK/logs/   results: $WORK/cmp.txt and $WORK/cmp_dijet_pt${PT}_*.pdf"
