#!/bin/bash
# Step 1 validation on one Perlmutter GPU (shared queue):
#   MG7 engine on GPU, MG7 legacy madevent, MG5_aMC reference, then gridpack timing
#   (GPU vs CPU) and the LHE comparison.
#
#   sbatch -A <your_account> perlmutter_validation.slurm
#   (override physics with e.g. sbatch --export=ALL,PTJ=200,NEVENTS=50000 ...)
#
#SBATCH -J mg7-validation
#SBATCH -C gpu
#SBATCH -q shared
#SBATCH -N 1
#SBATCH --gpus 1
#SBATCH -c 32
#SBATCH -t 02:00:00
#SBATCH -o mg7-validation-%j.out
set -euo pipefail

source "${MG7_BASE:-$PSCRATCH/mg7_athena}/env_mg7.sh"
HERE=${SLURM_SUBMIT_DIR:-$PWD}
export NEVENTS=${NEVENTS:-10000} PTJ=${PTJ:-100} ECM=${ECM:-13600} SEED=${SEED:-12345}
nvidia-smi -L

# 1. MG7 engine on the GPU (also writes a gridpack; CPU libs built too so the
#    gridpack can run on grid CPUs)
DEVICE="cpu, cuda" bash "$HERE/run_dijet.sh" mg7
# 2. MG7 running the legacy madevent workflow (what MadGraphControl would drive first)
bash "$HERE/run_dijet.sh" mg7_madevent
# 3. MG5_aMC reference
bash "$HERE/run_dijet.sh" mg5

cd "$MG7_BASE/runs"
# 4. gridpack: relocate it and time event generation on GPU vs CPU
GP=$(ls -td dijet_mg7_pt${PTJ}/Events/*/gridpack | head -1)
rm -rf gridpack_test && cp -r "$GP" gridpack_test && cd gridpack_test
for dev in cuda cpu; do
  echo "=== gridpack generation on $dev"
  /usr/bin/time -v python bin/generate_events --events "$NEVENTS" --seed 777 \
      --device $dev --verbosity log --run_name $dev 2>&1 | \
      grep -E "generating done|Elapsed|Maximum resident" || true
done
cd ..

# 5. compare
python "$HERE/compare_lhe.py" \
    dijet_mg5_pt${PTJ}.lhe.gz dijet_mg7_madevent_pt${PTJ}.lhe.gz dijet_mg7_pt${PTJ}.lhe.gz \
    --labels MG5 MG7-madevent MG7 --out cmp_dijet_pt${PTJ} | tee cmp_dijet_pt${PTJ}.txt

# timing summary from the logs
grep -E "^real" dijet_*_pt${PTJ}.log || true
