#!/usr/bin/env python3
"""Bring an MG7-engine run card (Cards/run_card.toml) to the MG5_aMC LO defaults, so MG7 and
MG5 samples are generated with the same acceptance.

    python mg7_mg5_defaults.py <mg7 process dir> [--maxjetflavor 4|5] [--dry-run]

Run it between 'output <dir>' and 'launch <dir>'. What it changes (checked against MG7 0.2.1 and
MG5_aMC 3.8.0 defaults):

  * photons: MG5 applies pta>10, |eta_a|<2.5, dR(a,a)>0.4, dR(a,j)>0.4, dR(a,l)>0.4 by default.
    The MG7 engine has NO default photon cuts, and it cannot do MG5's Frixione photon isolation
    (ptgmin/R0gamma/xn/epsgamma). The fixed-cone cuts are added here; isolation cannot be.
  * jet flavours: MG5 sets maxjetflavor=5 for 5-flavour models (sm-no_b_mass), so its ptj/etaj/
    drjj cuts also act on b quarks. The MG7 'jet' group stays u,d,s,c,g, and 'bottom' has no
    cuts, so in 5F a b-quark final state would be unconstrained. --maxjetflavor 5 puts b into
    'jet'. There is no 'set' command for multiparticles, so the TOML file is edited directly.
  * lepton cuts (ptl 10, |eta_l|<2.5, dR(l,l)>0.4, dR(j,l)>0.4; e, mu and tau) and jet cuts
    (ptj 20, |eta_j|<5, dR(j,j)>0.4) already match MG5 and are left alone.
Cuts on particle types absent from the process are harmless (MG5 hides them for the same reason).
"""
import argparse
import os
import sys

MG5_PHOTON_CUTS = {            # MG5 name -> (MG7 cut, bound, MG5 default)
    "pta":  ("photon-pt", "min", 10.0),
    "etaa": ("photon-eta_abs", "max", 2.5),
    "draa": ("photon-delta_r", "min", 0.4),
    "draj": ("photon-jet-delta_r", "min", 0.4),
    "dral": ("photon-lepton-delta_r", "min", 0.4),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("procdir")
    ap.add_argument("--maxjetflavor", type=int, choices=(4, 5), default=4)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    mg7_dir = os.environ.get("MG7_DIR")
    if not mg7_dir:
        sys.exit("MG7_DIR is not set (source env_mg7.sh)")
    sys.path.insert(0, mg7_dir)
    from madgraph.various.banner import RunCardMG7

    path = os.path.join(args.procdir, "Cards", "run_card.toml")
    card = RunCardMG7(path)
    cuts = card.dynamic_sections["cuts"]
    mps = card.dynamic_sections["multiparticles"]

    for mg5_name, (cut, bound, value) in MG5_PHOTON_CUTS.items():
        if bound not in cuts.get(cut, {}):
            card.set_cut("cuts.%s.%s" % (cut, bound), value)
            print("  %-6s -> %s.%s = %s" % (mg5_name, cut, bound, value))

    jet = list(mps["jet"])
    if args.maxjetflavor == 5 and 5 not in jet:
        mps["jet"] = jet[:4] + [5] + jet[4:8] + [-5] + jet[8:]
        # b now counts as a jet; keep a (cut-free) bottom group for b-tag-style cuts if wanted
        print("  maxjetflavor 5 -> jet = %s" % mps["jet"])
    elif args.maxjetflavor == 4 and (5 in jet or -5 in jet):
        mps["jet"] = [p for p in jet if abs(p) != 5]
        print("  maxjetflavor 4 -> jet = %s" % mps["jet"])

    if args.dry_run:
        card.write(sys.stdout)
        return
    card.write(path)
    print("updated %s" % path)


if __name__ == "__main__":
    main()
