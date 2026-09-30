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

<details>
<summary><b>Full MG5 → MG7 run-card parameter map (click to expand)</b></summary>

Generated from the MG7 0.2.1 source (`RunCardMG7._LO_SCALAR_MAP`, `_LO_DYNSCALE_MAP`, `_LO_CUT_MAP`,
`_LO_UNSUPPORTED` in `madgraph/various/banner.py`) and compared with the MG5_aMC 3.8.0 defaults.

**How `set` behaves in an MG7-engine launch script:** only the names in the first table (plus `iseed`) are
translated. The cut names in the third table exist only in MG7's run-card converter (`RunCardMG7.from_LO`). In a
launch script `set ptj 100` is **rejected with a warning and the run continues**, so use `set jet-pt.min 100`
(or `set cuts.<cut>.<min|max> <value>` for a cut not yet in the card).

### Parameters with an MG7 equivalent

| MG5 `run_card.dat` | MG7 `run_card.toml` |
|---|---|
| `nevents` | `generation.events` |
| `gridpack` | `gridpack.save_gridpack` |
| `fixed_ren_scale` | `beam.fixed_ren_scale` |
| `scalefact` | `beam.scale_factor` |
| `scale` | `beam.ren_scale` |
| `dsqrt_q2fact1` | `beam.fact_scale1` |
| `dsqrt_q2fact2` | `beam.fact_scale2` |
| `bwcutoff` | `phasespace.bw_cutoff` |
| `use_syst` | `systematics.enable` |
| `ebeam1` + `ebeam2` | `beam.e_cm` (sum) |
| `lpp1`/`lpp2` | `beam.leptonic` (true for lepton/no-PDF beams) |
| `fixed_fac_scale` | `beam.fixed_fact_scale` |
| `pdlabel`/`lhaid` | `beam.pdf` (LHAPDF set **name**) |
| `iseed` (0 = random) | `run.seed` (−1 = random) |
| `maxjetflavor` | `[multiparticles] jet = [...]` |
| `SDE_strategy` 1 / 2 | `phasespace.sde_strategy` = `diagrams` / `denominators` |

| MG5 `dynamical_scale_choice` | MG7 `beam.dynamical_scale_choice` |
|---|---|
| 1 | `transverse_energy` |
| 2 | `transverse_mass` |
| 3 | `half_transverse_mass` |
| 4 | `partonic_energy` |

| MG5 cut | MG7 `[cuts]` entry |
|---|---|
| `ptj` | `jet-pt.min` |
| `ptjmax` | `jet-pt.max` |
| `ptb` | `bottom-pt.min` |
| `ptbmax` | `bottom-pt.max` |
| `pta` | `photon-pt.min` |
| `ptamax` | `photon-pt.max` |
| `ptl` | `lepton-pt.min` |
| `ptlmax` | `lepton-pt.max` |
| `misset` | `missing-pt.min` |
| `missetmax` | `missing-pt.max` |
| `etaj` | `jet-eta_abs.max` |
| `etab` | `bottom-eta_abs.max` |
| `etaa` | `photon-eta_abs.max` |
| `etal` | `lepton-eta_abs.max` |
| `drjj` | `jet-delta_r.min` |
| `drjjmax` | `jet-delta_r.max` |
| `drbb` | `bottom-delta_r.min` |
| `drbbmax` | `bottom-delta_r.max` |
| `drll` | `lepton-delta_r.min` |
| `drllmax` | `lepton-delta_r.max` |
| `draa` | `photon-delta_r.min` |
| `draamax` | `photon-delta_r.max` |
| `drbj` | `bottom-jet-delta_r.min` |
| `drbjmax` | `bottom-jet-delta_r.max` |
| `draj` | `photon-jet-delta_r.min` |
| `drajmax` | `photon-jet-delta_r.max` |
| `drab` | `photon-bottom-delta_r.min` |
| `drabmax` | `photon-bottom-delta_r.max` |
| `drbl` | `bottom-lepton-delta_r.min` |
| `drblmax` | `bottom-lepton-delta_r.max` |
| `drjl` | `jet-lepton-delta_r.min` |
| `drjlmax` | `jet-lepton-delta_r.max` |
| `dral` | `photon-lepton-delta_r.min` |
| `dralmax` | `photon-lepton-delta_r.max` |
| `mmjj` | `jet-mass.min` |
| `mmjjmax` | `jet-mass.max` |
| `mmbb` | `bottom-mass.min` |
| `mmbbmax` | `bottom-mass.max` |
| `mmaa` | `photon-mass.min` |
| `mmaamax` | `photon-mass.max` |
| `mmll` | `lepton-mass.min` |
| `mmllmax` | `lepton-mass.max` |
| `dsqrt_shat` | `sqrt_s.min` |
| `dsqrt_shatmax` | `sqrt_s.max` |

### Changed defaults

| item | MG5_aMC 3.8.0 | MG7 0.2.1 engine |
|---|---|---|
| output mode | `output` → madevent | `output` → **mg7** engine (`output madevent` still available) |
| run card | `run_card.dat` | `run_card.toml` (sections `[run] [beam] [generation] [systematics] [phasespace] [cuts] [multiparticles] [madnis] [gridpack] [vegas] [histograms]`) |
| default PDF | `nn23lo1` (lhaid 230000) | `NNPDF40_lo_as_01180`; MG7 legacy madevent card: `lhapdf` / 331900 |
| α_s | built-in running for `nn23lo1` | always the tabulated α_s of the LHAPDF set |
| photon cuts | pta 10, etaa 2.5, draa 0.4, draj 0.4, dral 0.4 | **none** |
| photon isolation | Frixione (`ptgmin`, `R0gamma`, `xn`, `epsgamma`, `isoem`) | **not available** |
| jet definition in 5F | `maxjetflavor` → 5, jet cuts act on b | `jet` group stays u,d,s,c,g; `bottom` group has **no cuts** |
| jet / lepton cuts | ptj 20, etaj 5, drjj 0.4; ptl 10, etal 2.5, drll 0.4, drjl 0.4 | identical |
| HT/2 scale | `dynamical_scale_choice 3` | `half_transverse_mass` (identical definition) |
| random seed | `iseed = 0` → random | `run.seed = -1` → random (0 is a valid fixed seed) |
| event output | `unweighted_events.lhe.gz`, IDWTUP = −4 | `events.lhe.gz`, IDWTUP = 3; `lhe_npy`/`compact_npy` also available |
| scale-variation weights | include the nominal | 8 variations, **no nominal** entry |
| gridpack | tarball with `run.sh` | directory with `bin/generate_events` |
| SIMD / device | – | `run.device` (cpu, cuda, hip), `run.cpu_mode` (`auto` resolves to the build host) |
| phase-space integration | VEGAS multichannel | VEGAS + MadNIS normalising flows (`madnis.enable = auto`) |
| `sm` model and param_card | – | identical |

### Parameters with no MG7-engine equivalent (warned about or ignored)

`alpsfact`, `asrwgtflavor`, `auto_ptj_mjj`, `bias_module`, `bias_parameters`, `boost_event`, `chcluster`, `clusinfo`, `cut_decays`, `cutuse`, `deltaeta`, `dparameter`, `e_max_pdg`, `e_min_pdg`, `ea`, `eamax`, `eb`, `ebmax`, `ej`, `ejmax`, `el`, `elmax`, `epsgamma`, `eta_max_pdg`, `eta_min_pdg`, `etaamin`, `etabmin`, `etajmin`, `etalmin`, `etaonium`, `eva_xcut`, `evaorder`, `event_norm`, `fixed_extra_scale`, `frame_id`, `hel_filtering`, `hel_recycling`, `hel_splitamp`, `hel_zeroamp`, `highestmult`, `ht2max`, `ht2min`, `ht3max`, `ht3min`, `ht4max`, `ht4min`, `htjmax`, `htjmin`, `ickkw`, `ievo_eva`, `ihtmax`, `ihtmin`, `iseed`, `isoem`, `ktdurham`, `ktscheme`, `lhe_version`, `limhel`, `mass_ion1`, `mass_ion2`, `me_frame`, `mmnl`, `mmnlmax`, `mue_over_ref`, `mue_ref_fixed`, `mxx_min_pdg`, `mxx_only_part_antipart`, `nb_neutron1`, `nb_neutron2`, `nb_proton1`, `nb_proton2`, `nhel`, `pdfwgt`, `pdgs_for_merging_cut`, `polbeam1`, `polbeam2`, `pt_max_pdg`, `pt_min_pdg`, `ptgmin`, `ptheavy`, `ptj1max`, `ptj1min`, `ptj2max`, `ptj2min`, `ptj3max`, `ptj3min`, `ptj4max`, `ptj4min`, `ptl1max`, `ptl1min`, `ptl2max`, `ptl2min`, `ptl3max`, `ptl3min`, `ptl4max`, `ptl4min`, `ptllmax`, `ptllmin`, `ptlund`, `ptonium`, `r0gamma`, `scalefact`, `sys_alpsfact`, `sys_matchscale`, `sys_pdf`, `sys_scalecorrelation`, `sys_scalefact`, `systematics_arguments`, `systematics_program`, `xetamin`, `xn`, `xpta`, `xptb`, `xptj`, `xptl`, `xqcut`

In words: beam polarisation and heavy ions; MLM/CKKW(-L) merging (`ickkw`, `xqcut`, `ktdurham`, …); bias modules;
per-leg ordered pT cuts (`ptj1min` …), HT cuts, energy cuts and η-minimum cuts; per-PDG cuts; photon isolation;
helicity controls; MG5 systematics-program options; EVA and frame options.
`scalefact` appears in both the translated list and this list in the 0.2.1 source; `set scalefact` is translated
to `beam.scale_factor`.

</details>

## Usage (Perlmutter)

```bash
bash nersc/setup_mg7.sh
source $PSCRATCH/mg7_athena/env_mg7.sh
conda install -y -c conda-forge lhapdf           # for PDF_MODE=lhapdf
bash nersc/highstats_submit.sh <account> 10000000
```
