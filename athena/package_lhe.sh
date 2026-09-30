#!/bin/bash
# Turn an MG7 (or MG5) events file into the TXT tarball Gen_tf expects for --inputGeneratorFile:
# a .tar.gz that contains a single file ending in ".events".
#
#   bash package_lhe.sh <events.lhe.gz> <output_stem>
#   e.g. bash package_lhe.sh dijet_mg7_pt100.lhe.gz mg7_jj_pT100._00001
#        -> mg7_jj_pT100._00001.tar.gz  (contains mg7_jj_pT100._00001.events)
#
# Use the same naming as for the Pepper validation LHE when the file goes through LHE registration.
set -euo pipefail
IN=${1:?input lhe(.gz)}
STEM=${2:?output stem}

TMP=$(mktemp -d)
if [[ "$IN" == *.gz ]]; then gunzip -c "$IN" > "$TMP/$STEM.events"; else cp "$IN" "$TMP/$STEM.events"; fi

# basic sanity: well-formed file, event count, <init> block
NEV=$(grep -c "<event>" "$TMP/$STEM.events")
grep -q "</LesHouchesEvents>" "$TMP/$STEM.events" || { echo "ERROR: truncated LHE (no closing tag)"; exit 1; }
echo "events: $NEV"
sed -n '/<init>/,/<\/init>/p' "$TMP/$STEM.events"

tar czf "$STEM.tar.gz" -C "$TMP" "$STEM.events"
rm -rf "$TMP"
ls -l "$STEM.tar.gz"
