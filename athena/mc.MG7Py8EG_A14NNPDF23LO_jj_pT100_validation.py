#--------------------------------------------------------------------------------------------
# MadGraph7 (alpha) LO dijet, pT(j) > 100 GeV, showered with Pythia8 A14 NNPDF2.3LO + EvtGen.
# VALIDATION ONLY (split workflow): the LHE file is produced standalone with MG7 on a GPU node
# (nersc/run_dijet.sh) and passed to Gen_tf with --inputGeneratorFile. No MG7 code runs in Athena.
#
# Put this file in a mcjoboptions checkout under a placeholder DSID directory (e.g. 999xxx/999999/)
# alongside the Pepper validation jO, and align the includes with that jO if they differ.
#--------------------------------------------------------------------------------------------
evgenConfig.description = "MadGraph7 (alpha, validation) LO pp->jj, pT(j)>100 GeV, Pythia8 A14 NNPDF23LO, EvtGen"
evgenConfig.generators  = ["MadGraph", "Pythia8", "EvtGen"]
evgenConfig.keywords    = ["SM", "QCD", "jets", "dijet"]
evgenConfig.contact     = ["<name> <cern email>"]
evgenConfig.nEventsPerJob = 10000
# one LHE tarball per job; its events must cover nEventsPerJob after the shower
evgenConfig.inputFilesPerJob = 1

# Shower: same tune/PDF as the ATLAS default for LO MadGraph + Pythia8 samples.
include("Pythia8_i/Pythia8_A14_NNPDF23LO_EvtGen_Common.py")
# Reads the LHE file handed over by Gen_tf (Pythia8_MadGraph.py pulls in Pythia8_LHEF.py and
# the MG-specific settings). The LHE is unmerged LO: no CKKW-L / MLM settings are needed.
include("Pythia8_i/Pythia8_MadGraph.py")

# MG7 notes relevant for this sample (see README):
#  * MG7-engine LHE files are LHEF 3.0 with IDWTUP=3 (MG5 madevent writes -4); each event
#    weight equals sigma in pb, as with MG5 unweighted events.
#  * The <initrwgt> block has the 8 scale variations but not the nominal (MUR=MUF=1) entry,
#    unlike MG5 systematics. Check the weight names Pythia8_i reports in the log.
#  * The header has <MG5ProcCard>, <slha>, <MG7RunCard>, <MG7Seed>; there is no <MGRunCard>
#    and no <MGGenerationInfo> block.
