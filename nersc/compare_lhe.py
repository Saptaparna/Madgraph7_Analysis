#!/usr/bin/env python3
"""Compare parton-level LHE files (MG7 vs MG7-madevent vs MG5 vs Pepper, ...).

    python compare_lhe.py dijet_mg5_pt100.lhe.gz dijet_mg7_pt100.lhe.gz \
        --labels MG5 MG7 --out cmp_dijet [--jobs 3] [--max-events N]

Events are streamed into fixed histograms, so memory does not grow with the sample size
(10M-event files are fine). Files are processed in parallel (one process per file).
Prints the cross section +- error from each <init> block, the ratio to the first file,
and a chi2/ndf per observable. With matplotlib, it also writes one PDF per observable
with a ratio panel. Needs only numpy (matplotlib optional).
"""
import argparse
import gzip
import math
import sys
from multiprocessing import Pool

import numpy as np

JET_IDS = {1, 2, 3, 4, 5, 21}
LEP_IDS = {11, 13, 15}

# Fixed binning (streaming cannot look at the data first). Log bins for falling spectra.
BINS = {
    "j1_pt":  np.geomspace(20, 4000, 41),
    "j2_pt":  np.geomspace(20, 4000, 41),
    "j3_pt":  np.geomspace(20, 2000, 31),
    "j1_eta": np.linspace(-5, 5, 41),
    "j2_eta": np.linspace(-5, 5, 41),
    "jet_eta":  np.linspace(-5, 5, 41),     # every jet (independent of how jets are ordered)
    "fwd_abseta": np.linspace(0, 5, 26),   # the more forward of the two leading jets
    "ctr_abseta": np.linspace(0, 5, 26),   # the more central one
    "mjj":    np.geomspace(40, 13000, 46),
    "ystar":  np.linspace(0, 5, 26),          # |y1 - y2| / 2 : dijet angular variable
    "dphijj": np.linspace(0, math.pi, 33),
    "njet":   np.arange(-0.5, 8.5, 1.0),
    "ht":     np.geomspace(40, 8000, 41),
    "l1_pt":  np.geomspace(5, 3000, 41),
    "mll":    np.geomspace(5, 5000, 41),
    # incoming-parton momentum fractions x = E / E_beam (PDF region probed)
    "x_max":  np.geomspace(1e-3, 1, 31),
    "x_min":  np.geomspace(1e-5, 1, 41),
}
XLABELS = {
    "j1_pt": "leading-jet $p_T$ [GeV]", "j2_pt": "second-jet $p_T$ [GeV]", "j3_pt": "third-jet $p_T$ [GeV]",
    "j1_eta": r"leading-jet $\eta$", "j2_eta": r"second-jet $\eta$", "jet_eta": r"jet $\eta$ (all jets)",
    "fwd_abseta": r"$|\eta|$ of the more forward jet", "ctr_abseta": r"$|\eta|$ of the more central jet",
    "mjj": "$m_{jj}$ [GeV]", "ystar": r"$y^* = |y_1 - y_2|/2$", "dphijj": r"$\Delta\phi_{jj}$",
    "njet": "number of jets", "ht": "$H_T$ [GeV]", "l1_pt": "leading-lepton $p_T$ [GeV]",
    "mll": r"$m_{\ell\ell}$ [GeV]", "x_max": "larger parton $x$", "x_min": "smaller parton $x$",
}
LOG_X = {"j1_pt", "j2_pt", "j3_pt", "mjj", "ht", "l1_pt", "mll", "x_max", "x_min"}


def kin(p):
    px, py, pz, e = p
    pt = math.hypot(px, py)
    pabs = math.sqrt(px * px + py * py + pz * pz)
    eta = 0.5 * math.log((pabs + pz) / (pabs - pz)) if pabs > abs(pz) else math.copysign(20.0, pz)
    y = 0.5 * math.log((e + pz) / (e - pz)) if e > abs(pz) else math.copysign(20.0, pz)
    return pt, eta, math.atan2(py, px), y


def minv(a, b):
    e, px, py, pz = a[3] + b[3], a[0] + b[0], a[1] + b[1], a[2] + b[2]
    return math.sqrt(max(e * e - px * px - py * py - pz * pz, 0.0))


EBEAM = [None]   # set per file from the <init> block


def event_values(parts):
    """Observable values of one event, as a list of (name, value)."""
    fs = [p for p in parts if p[1] == 1]
    xs = sorted(p[5] / EBEAM[0] for p in parts if p[1] == -1) if EBEAM[0] else []
    jets = sorted([p[2:] for p in fs if abs(p[0]) in JET_IDS], key=lambda q: -(q[0] * q[0] + q[1] * q[1]))
    leps = sorted([p[2:] for p in fs if abs(p[0]) in LEP_IDS], key=lambda q: -(q[0] * q[0] + q[1] * q[1]))
    out = [("njet", len(jets)), ("ht", sum(math.hypot(j[0], j[1]) for j in jets))]
    out += [("jet_eta", kin(j)[1]) for j in jets]
    if jets:
        pt1, eta1, phi1, y1 = kin(jets[0])
        out += [("j1_pt", pt1), ("j1_eta", eta1)]
    if len(jets) >= 2:
        pt2, eta2, phi2, y2 = kin(jets[1])
        d = abs(phi1 - phi2)
        out += [("j2_pt", pt2), ("j2_eta", eta2), ("mjj", minv(jets[0], jets[1])),
                ("dphijj", min(d, 2 * math.pi - d)), ("ystar", abs(y1 - y2) / 2),
                ("fwd_abseta", max(abs(eta1), abs(eta2))), ("ctr_abseta", min(abs(eta1), abs(eta2)))]
    if len(jets) >= 3:
        out.append(("j3_pt", kin(jets[2])[0]))
    if leps:
        out.append(("l1_pt", kin(leps[0])[0]))
    if len(leps) >= 2:
        out.append(("mll", minv(leps[0], leps[1])))
    if len(xs) == 2:
        out += [("x_min", xs[0]), ("x_max", xs[1])]
    return out


def next_data(it):
    """Next non-blank, non-comment line, split (some writers put blank lines inside <event>)."""
    for line in it:
        t = line.split()
        if t and not t[0].startswith("#"):
            return t
    raise EOFError("truncated LHE file")


def process_file(args):
    """Stream one LHE file. Returns xsec, xerr, idwtup, n_events, sum of weight signs, and
    per-observable (sum w_sign, sum w_sign^2) histograms, normalised later."""
    path, max_events = args
    opener = gzip.open if path.endswith(".gz") else open
    xsec = xerr = idwtup = None
    h = {k: np.zeros(len(b) - 1) for k, b in BINS.items()}
    h2 = {k: np.zeros(len(b) - 1) for k, b in BINS.items()}
    # buffer values per observable and flush with np.histogram in chunks (fast)
    buf = {k: [] for k in BINS}
    bufw = {k: [] for k in BINS}
    n = 0
    sign_sum = 0.0

    def flush():
        for k in BINS:
            if buf[k]:
                v = np.asarray(buf[k]); w = np.asarray(bufw[k])
                h[k] += np.histogram(v, bins=BINS[k], weights=w)[0]
                h2[k] += np.histogram(v, bins=BINS[k], weights=w * w)[0]
                buf[k].clear(); bufw[k].clear()

    with opener(path, "rt") as f:
        it = iter(f)
        for line in it:
            s = line.strip()
            if s == "<init>" or s.startswith("<init "):
                rows = []
                for l2 in it:
                    t = l2.strip()
                    if t == "</init>":
                        break
                    if t and not t.startswith("<") and not t.startswith("#"):
                        rows.append(t)
                beam = rows[0].split()
                idwtup, nproc = int(beam[8]), int(beam[9])
                EBEAM[0] = float(beam[2])
                procs = [list(map(float, r.split()[:3])) for r in rows[1:1 + nproc]]
                xsec = sum(p[0] for p in procs)
                xerr = math.sqrt(sum(p[1] ** 2 for p in procs))
                continue
            if s == "<event>" or s.startswith("<event "):
                head = next_data(it)
                nup, wgt = int(head[0]), float(head[2])
                parts = []
                for _ in range(nup):
                    t = next_data(it)
                    parts.append((int(t[0]), int(t[1]), float(t[6]), float(t[7]), float(t[8]), float(t[9])))
                ws = 1.0 if wgt >= 0 else -1.0
                sign_sum += ws
                for k, v in event_values(parts):
                    buf[k].append(v); bufw[k].append(ws)
                n += 1
                if n % 200000 == 0:
                    flush()
                if max_events and n >= max_events:
                    break
    flush()
    return xsec, xerr, idwtup, n, sign_sum, h, h2


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--labels", nargs="+")
    ap.add_argument("--out", default="lhe_compare")
    ap.add_argument("--max-events", type=int, default=None)
    ap.add_argument("--jobs", type=int, default=None, help="parallel processes (default: one per file)")
    args = ap.parse_args()
    labels = args.labels or [f.split("/")[-1] for f in args.files]
    if len(labels) != len(args.files):
        sys.exit("need one label per file")

    with Pool(args.jobs or len(args.files)) as pool:
        results = pool.map(process_file, [(f, args.max_events) for f in args.files])

    print(f"{'sample':<22}{'xsec [pb]':>16}{'error':>14}{'rel.err':>9}{'events':>11}{'IDWTUP':>8}")
    samples = []
    for lab, (xs, xe, idw, n, ssum, h, h2) in zip(labels, results):
        print(f"{lab:<22}{xs:>16.6g}{xe:>14.4g}{100 * xe / xs:>8.3f}%{n:>11d}{idw:>8d}")
        # unweighted events: each carries +-xsec / (sum of signs)
        scale = xs / ssum if ssum else 0.0
        hist = {}
        for k in BINS:
            width = np.diff(BINS[k])
            hist[k] = (h[k] * scale / width, np.sqrt(h2[k]) * abs(scale) / width)
        samples.append((lab, xs, xe, n, hist))
    ref = samples[0]
    for lab, xs, xe, n, _ in samples[1:]:
        pull = (xs - ref[1]) / math.hypot(xe, ref[2])
        print(f"  {lab} / {ref[0]} = {xs / ref[1]:.5f}   ({pull:+.2f} sigma)")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        plt = None
        print("matplotlib not available: printing chi2 only")

    print("\nshape comparison (dsigma/dx, each sample normalised to its own xsec; chi2/ndf vs first file)")
    written = 0
    for name, bins in BINS.items():
        href, eref = ref[4][name]
        if np.count_nonzero(href) < 2:
            continue   # absent from this final state, or fixed by kinematics (njet, dphi for 2->2)
        line = f"  {name:<8}"
        for lab, _, _, _, hist in samples[1:]:
            hv, ev = hist[name]
            m = (eref > 0) & (ev > 0)
            chi2 = np.sum((hv[m] - href[m]) ** 2 / (ev[m] ** 2 + eref[m] ** 2))
            line += f"  {lab}: {chi2:.1f}/{m.sum()}"
        print(line)
        if plt is None:
            continue
        fig, (ax, rx) = plt.subplots(2, 1, sharex=True, figsize=(6, 5.5),
                                     gridspec_kw={"height_ratios": [3, 1], "hspace": 0.05})
        centers = np.sqrt(bins[1:] * bins[:-1]) if name in LOG_X else 0.5 * (bins[1:] + bins[:-1])
        for i, (lab, _, _, _, hist) in enumerate(samples):
            hv, ev = hist[name]
            ax.stairs(hv, bins, label=lab, color=f"C{i}")
            ax.errorbar(centers, hv, ev, fmt="none", lw=0.8, color=f"C{i}")
            if i:
                with np.errstate(divide="ignore", invalid="ignore"):
                    r = np.where(href > 0, hv / href, np.nan)
                    re_ = np.where(href > 0, np.hypot(ev / np.where(hv > 0, hv, 1) , eref / np.where(href > 0, href, 1)) * r, np.nan)
                rx.errorbar(centers, r, re_, fmt="o", ms=2, color=f"C{i}")
        rx.axhline(1, color="grey", lw=0.8)
        rx.set_ylim(0.9, 1.1)
        others = ", ".join(smp[0] for smp in samples[1:])
        rx.set_ylabel(f"{others}\n/ {ref[0]}" if len(samples) == 2 else f"Ratio to\n{ref[0]}", fontsize=10)
        rx.set_xlabel(XLABELS.get(name, name), fontsize=11)
        ax.set_ylabel("dσ/dx [pb / unit]", fontsize=11)
        fig.align_ylabels([ax, rx])
        if name in LOG_X:
            ax.set_yscale("log"); ax.set_xscale("log")
        ax.legend()
        fig.savefig(f"{args.out}_{name}.pdf", bbox_inches="tight", pad_inches=0.15)
        plt.close(fig)
        written += 1
    if plt is not None:
        print(f"\n{written} plots written to {args.out}_<observable>.pdf")


if __name__ == "__main__":
    main()
