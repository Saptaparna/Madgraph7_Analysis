#!/bin/bash
# Generate the same LO dijet setup with MG7 (new engine), MG7 in legacy madevent mode, or MG5_aMC.
#
#   source $PSCRATCH/mg7_athena/env_mg7.sh
#   bash run_dijet.sh mg7            # GPU (default DEVICE=cuda)
#   DEVICE=cpu bash run_dijet.sh mg7 # same, CPU only
#   bash run_dijet.sh mg7_madevent   # MG7 'output madevent' (what MadGraphControl would drive first)
#   bash run_dijet.sh mg5            # MG5_aMC reference
#
# Physics settings are shared via the variables below; match them to the Pepper dijet
# validation sample if you want a three-way comparison.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MODE=${1:?usage: run_dijet.sh mg7|mg7_madevent|mg5}
NEVENTS=${NEVENTS:-10000}
SEED=${SEED:-12345}
PTJ=${PTJ:-100}          # jet pT cut [GeV]
ETAJ=${ETAJ:-5.0}
DRJJ=${DRJJ:-0.4}
ECM=${ECM:-13600}        # Run 3; use 13000 to compare with Run 2 samples
DEVICE=${DEVICE:-cuda}   # mg7 only: cpu | cuda | "cpu, cuda"
CPU_MODE=${CPU_MODE:-simd_256}   # mg7 only: fixed SIMD width -> portable libraries (auto may pick avx512)
GRIDPACK=${GRIDPACK:-True}       # mg7 only
WORK=${WORK:-$MG7_BASE/runs}
MAXJETFLAVOR=${MAXJETFLAVOR:-4}  # 4: 'import model sm'; 5: 'import model sm-no_b_mass' (b counted as jet)
PROC=${PROC:-p p > j j}          # any LO process; the jet cuts above apply to it
TAG=${TAG:-dijet}                # name prefix for the output directories
PDF_MODE=${PDF_MODE:-builtin}    # mg5/mg7_madevent only: builtin (nn23lo1) | lhapdf (same LHAPDF set as the MG7 engine)
if [ "$MAXJETFLAVOR" = 5 ]; then MODEL=sm-no_b_mass; else MODEL=sm; fi

mkdir -p "$WORK"
cd "$WORK"
EBEAM=$(python -c "print($ECM/2)")
NAME=${TAG}_${MODE}_pt${PTJ}
if [ "$PDF_MODE" = lhapdf ] && [ "$MODE" != mg7 ]; then
  NAME=${NAME}_lhapdf
  command -v lhapdf-config >/dev/null || { echo "PDF_MODE=lhapdf needs lhapdf-config (conda install -c conda-forge lhapdf)"; exit 1; }
fi
rm -rf "$NAME"

case "$MODE" in
mg7)
  # New MG7 engine: TOML run card (Cards/run_card.toml). Legacy cut names such as
  # 'set ptj' are REJECTED with only a warning, so cuts use the [cuts] syntax.
  cat > "$NAME.gen.mg" <<EOF
set automatic_html_opening False
import model $MODEL
generate $PROC
output $NAME
EOF
  python "$MG7_DIR/bin/madgraph" "$NAME.gen.mg" 2>&1 | tee "$NAME.log"
  # MG5-equivalent defaults the MG7 engine does not apply by itself: photon cuts
  # (pta/etaa/draa/draj/dral) and b quarks in the jet group for 5-flavour runs.
  python "$SCRIPT_DIR/mg7_mg5_defaults.py" "$NAME" --maxjetflavor "$MAXJETFLAVOR" | tee -a "$NAME.log"
  cat > "$NAME.mg" <<EOF
launch $NAME
set run.device $DEVICE
set run.cpu_mode $CPU_MODE
set run.seed $SEED
set run.output_format lhe
set run.verbosity log
set beam.e_cm $ECM
set beam.pdf NNPDF23_lo_as_0130_qed
set beam.dynamical_scale_choice half_transverse_mass
set generation.events $NEVENTS
set systematics.enable True
set systematics.pdf central
set gridpack.save_gridpack $GRIDPACK
set gridpack.include_madspace True
set jet-pt.min $PTJ
set jet-eta_abs.max $ETAJ
set jet-delta_r.min $DRJJ
done
EOF
  ( time python "$MG7_DIR/bin/madgraph" "$NAME.mg" ) 2>&1 | tee -a "$NAME.log"
  LHE=$(ls -t "$NAME"/Events/*/events.lhe.gz | head -1)
  ;;
mg7_madevent|mg5)
  # Legacy LO workflow, identical card syntax in both codes.
  if [ "$MODE" = mg5 ]; then EXE="$MG5_DIR/bin/mg5_aMC"; else EXE="python $MG7_DIR/bin/madgraph"; fi
  cat > "$NAME.gen.mg" <<EOF
set automatic_html_opening False
import model $MODEL
generate $PROC
$( [ "$PDF_MODE" = lhapdf ] && echo "set lhapdf $(command -v lhapdf-config)" )
output madevent $NAME
EOF
  $EXE "$NAME.gen.mg" 2>&1 | tee "$NAME.log"
  # The default run_card asks for LHAPDF (pdlabel=lhapdf) and 'launch' links LHAPDF
  # before any 'set' command is read. Switch the card to nn23lo1, MG's built-in copy
  # of NNPDF23_lo_as_0130_qed, so no LHAPDF library is needed.
  if [ "$PDF_MODE" = lhapdf ]; then
    # NNPDF23_lo_as_0130_qed through LHAPDF, alpha_s from the set: identical inputs to the MG7 engine
    # (MG5 3.8 defaults to pdlabel=nn23lo1, MG7's legacy card to lhapdf/331900: set both explicitly)
    sed -i -E 's/^ *[a-zA-Z0-9_]+ *= *pdlabel /     lhapdf = pdlabel /' "$NAME/Cards/run_card.dat"
    sed -i -E 's/^ *[0-9]+ *= *lhaid /     247000 = lhaid /' "$NAME/Cards/run_card.dat"
  else
    sed -i -E 's/^ *[a-zA-Z0-9_]+ *= *pdlabel /     nn23lo1 = pdlabel /' "$NAME/Cards/run_card.dat"
  fi
  grep "= pdlabel" "$NAME/Cards/run_card.dat"
  # madevent is not meant to make more than ~1M events in one run: above CHUNK events, split
  # into NRUN runs with 'multi_run' (different seeds, merged into one file with a combined xsec)
  CHUNK=${CHUNK:-1000000}
  if [ "$NEVENTS" -gt "$CHUNK" ]; then
    NRUN=$(( (NEVENTS + CHUNK - 1) / CHUNK )); PERRUN=$(( NEVENTS / NRUN ))
    LAUNCH="launch $NAME -i
multi_run $NRUN"
    echo "multi_run: $NRUN runs x $PERRUN events"
  else
    PERRUN=$NEVENTS; LAUNCH="launch $NAME"
  fi
  cat > "$NAME.launch.mg" <<EOF
$LAUNCH
set nevents $PERRUN
set iseed $SEED
set ebeam1 $EBEAM
set ebeam2 $EBEAM
set dynamical_scale_choice 3
set use_syst False
set ptj $PTJ
set etaj $ETAJ
set drjj $DRJJ
set maxjetflavor $MAXJETFLAVOR
set xqcut 0
set ickkw 0
done
EOF
  ( time $EXE "$NAME.launch.mg" ) 2>&1 | tee -a "$NAME.log"
  # merged/single run is Events/run_NN (multi_run sub-runs are run_NN_k)
  LHE=$(ls -t "$NAME"/Events/run_[0-9][0-9]/unweighted_events.lhe.gz | head -1)
  if [ "${KEEP_SUBRUNS:-0}" != 1 ]; then rm -rf "$NAME"/Events/run_[0-9][0-9]_[0-9]*; fi
  ;;
*) echo "unknown mode $MODE"; exit 1;;
esac

echo "LHE file: $WORK/$LHE"
ln -sf "$WORK/$LHE" "$WORK/$NAME.lhe.gz"
