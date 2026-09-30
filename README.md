# Madgraph7_Analysis

Validation of **MadGraph7** (alpha, v0.2.1, commit `a805b96`) against **MadGraph5_aMC@NLO 3.8.0** at parton level,
and tooling for feeding MG7 events into the ATLAS Athena generation chain (Pythia8 shower via `Gen_tf.py`).

Author: Saptaparna Bhattacharya

## Result: LO pp → jj, 13.6 TeV, pT(j) > 100 GeV, 10M events per sample

Common setup: `sm` model (4 flavours), NNPDF2.3 LO (α_s = 0.130), scale H_T/2, |η_j| < 5, ΔR_jj > 0.4.
MG7 ran on one NVIDIA A100 (NERSC Perlmutter). MG5 ran on one 128-core CPU node (`multi_run` 10 × 1M).

| sample | σ [pb] | rel. error |
|---|---|---|
| MG5, built-in `nn23lo1` | 1.37226e6 | 0.006 % |
| MG5, LHAPDF 247000 | 1.37976e6 | 0.006 % |
| **MG7, LHAPDF 247000 (GPU)** | **1.37964e6** | 0.010 % |

* **MG7 / MG5 (same PDF input) = 0.99991 (−0.7σ).**
* Shapes, MG7 vs MG5-LHAPDF, as χ²/ndf ([`results/dijet_pt100_10M/mg7_vs_mg5_lhapdf.txt`](results/dijet_pt100_10M/mg7_vs_mg5_lhapdf.txt)):
  jet pT 13/22, H_T 13/22, m_jj 23/30, y* 27/22, jet η (all jets) 36/40, |η| of the more central jet 16/22,
  |η| of the more forward jet 36/24 (the last two bins, near the |η| < 5 cut, are 1–2σ low), parton x_min 26/27, x_max 28/19.
* The η distributions of the "leading" and "second" jet individually differ (96/38, 62/39). At LO the two jets have
  identical pT, so "leading" is simply the first parton in the event record. MG7 orders partons differently from MG5:
  in qg events it always lists the gluon first, including when it comes from the −z beam. The ordering-independent
  η observables above agree.
* The built-in `nn23lo1` and the LHAPDF version of NNPDF2.3 LO differ by +0.55 % in σ, growing to a few percent at
  high pT (α_s running / grid interpolation). This is an MG5 PDF-input effect, not MG7.
* Timing for 10M events: MG7 took 72 s wall in total on one A100 (6.5 s of it event generation), MG5 about 30 min
  on 128 CPU cores.

Plots are in [`results/dijet_pt100_10M/plots/`](results/dijet_pt100_10M/plots/).

## Contents

| path | purpose |
|---|---|
| `nersc/setup_mg7.sh` | installs MG7 + madspace (CPU SIMD + CUDA) and MG5 on Perlmutter; writes `env_mg7.sh` |
| `nersc/run_dijet.sh` | one LO setup in three modes: `mg7` (new engine), `mg7_madevent` (MG7 legacy LO), `mg5`. Options: `NEVENTS`, `PTJ`, `ECM`, `PROC`, `TAG`, `MAXJETFLAVOR`, `PDF_MODE=builtin\|lhapdf`, `DEVICE`; splits madevent runs above 1M events with `multi_run` |
| `nersc/mg7_mg5_defaults.py` | adds the MG5 default cuts that the MG7 engine lacks (photon pt/η/ΔR cuts; b quarks in the jet group for 5F) to `run_card.toml` |
| `nersc/compare_lhe.py` | streams any number of LHE files into fixed histograms: σ ± error, shape χ², PDF plots with ratio panels |
| `nersc/perlmutter_validation.slurm` | small three-way validation on one GPU node, plus gridpack timing |
| `nersc/highstats_submit.sh` | 10M-event comparison as four Slurm jobs (MG7 GPU, MG5 builtin, MG5 LHAPDF, comparison) |
| `athena/` | job options, LHE packaging and a `Gen_tf.py` wrapper to shower MG7 LHE with Pythia8 A14 + EvtGen |

## MG5 → MG7 differences to keep in mind (MG7 0.2.1)

* The MG7 engine uses a TOML run card (`Cards/run_card.toml`). Legacy `set ptj ...`-style cut names are ignored with
  only a warning. Use `set jet-pt.min 100` or `set cuts.<cut>.<min|max> <value>`.
* No default photon cuts (MG5 applies pta 10, |η_a| < 2.5, ΔR 0.4), and no Frixione photon isolation.
* For 5-flavour models the `jet` group does not include b quarks, and the `bottom` group has no cuts.
* No MLM/CKKW merging or bias module in the new engine.
* α_s comes from the LHAPDF set's table. Compare against MG5 with `pdlabel = lhapdf`, not the built-in PDFs.
* LHE: IDWTUP = 3, and the scale-variation `<rwgt>` block has no nominal entry.
* The gridpack is a directory with `bin/generate_events`. `--verbosity none` crashes (use `log`).

## Usage (Perlmutter)

```bash
bash nersc/setup_mg7.sh
source $PSCRATCH/mg7_athena/env_mg7.sh
conda install -y -c conda-forge lhapdf           # for PDF_MODE=lhapdf
bash nersc/highstats_submit.sh <account> 10000000
```
