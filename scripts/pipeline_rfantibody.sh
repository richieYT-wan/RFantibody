#!/bin/bash

# ============================================================================
# Full Nanobody Design Pipeline
# ============================================================================
# This script runs the complete nanobody design workflow:
#   1. RFdiffusion  - Design nanobody backbone structures
#   2. ProteinMPNN  - Design sequences for the backbones
#   3. RF2          - Predict/refine final structures
# Usage: bash /scripts/rfantibody_pipeline.sh
# ============================================================================

set -euo pipefail # Exit on error
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Walk up until we find RFantibody
ROOTDIR="$SCRIPT_DIR"
while [[ "$ROOTDIR" != "/" && "$(basename "$ROOTDIR")" != "RFantibody" ]]; do
  ROOTDIR="$(dirname "$ROOTDIR")"
done

if [[ "$(basename "$ROOTDIR")" != "RFantibody" ]]; then
  echo "Error: Could not locate RFantibody root directory."
  exit 1
fi
# ============================================================================
# INPUT PARAMETERS // ARGUMENT PARSING DEFINITION
# ============================================================================

# Default parameters handling before parsing.
# TODO: Make a script to wget raw PDB structures from RCSB, convert them to Chothia then to HLT?
# TODO: Make a script to wget a SAbDab Chothia PDB structure, convert them to HLT
# TODO: Make a script to wget target structures ? (low-priority for now)

# RFdiffusion parameters
FRAMEWORK=""              # TO BE PARSED required; RFAntibody expects frameworks in "HLT" format, which is created using from a Chothia-annotated PDB using ./scripts/util/chothia2HLT.py
TARGET=""                 # TO BE PARSED required;
OUTPUTDIR="run_000"          # name of the output directory. ex: "run_cd33_001" will write outputs in "${HOMEDIR}outputs/run_cd33_001/"
N_DESIGNS=100             # Number of designs to generate (default: 100 backbones)
DIFFUSER_T=50             # Diffusion time-steps (default: 50)
DESIGN_LOOPS="H1:7,H2:6,H3:6-20"           # Loops to design with or without length;
                          # ex: "H1:7,H2:6,H3:5-13" to make H1,H2,H3 loops with lengths 7, 6 and ranging 5 to 13
HOTSPOTS=""               # Hotspot residues on target, uses the target chain identifier; ex: "B107,B112,B115" (empty means not used)
# ProteinMPNN parameters ; missing : --augment-eps FLOAT --> backbone noise augmentation
LOOPS=$(echo "$DESIGN_LOOPS" | sed 's/:[^,]*//g') # Parses the DESIGN_LOOPS and removes lengths
N_SEQS=10                  # Number of sequences to generate per backbone (default: 10 seqs / backbone)
TEMP=0.2                  # ProteinMPNN sampling temp (default: 0.2)
# RF2 parameters ;
N_RECYCLES=10             # Number of recycling steps in RF2 (default: 10)
RF2_SEED=""                # RF2 seed for reproducibility (Optional: empty string means do not use, otherwise integer)
HOTSPOT_PROP=0.1          # Proportion of hotspot residues to show to model (default: 0.1)

#!/usr/bin/env bash
set -euo pipefail

echo $0
# ============================================================================
# USAGE + ERROR HANDLING
# ============================================================================

usage() {
  cat <<'EOF'
Usage:
  pipeline_rfantibody.sh --framework FRAMEWORK_HLT.pdb --target TARGET.pdb --output-dir RUN_NAME [options]

Required arguments:
  --framework PATH        VHH framework in HLT format (from Chothia PDB)
  --target PATH           Target structure (PDB; cleaned recommended)
  --output-dir NAME       Run/output directory name (ex: run_cd33_001)
  --rfdiff-det STR        true
Optional arguments:
  --n-designs INT         Number of backbones to generate (default: 100)
  --diffuser-t INT        RFdiffusion timesteps (default: 50)
  --design-loops STR      Loops to design with lengths (default: H1:7,H2:6,H3:6-20)
                          Example: "H1:7,H2:6,H3:5-13"
  --hotspots STR          Hotspot residues on target (default: empty/off)
                          Example: "B107,B112,B115"

  --n-seqs INT            Sequences per backbone (default: 10)
  --temp FLOAT            ProteinMPNN sampling temperature (default: 0.2)

  --n-recycles INT        RF2 recycle steps (default: 10)
  --rf2-seed INT          RF2 seed (optional; default: empty/unset)
  --hotspot-prop FLOAT    Fraction of hotspots shown to RF2 (default: 0.1)

Flags:
  --dry-run               Print actions, do not execute heavy steps
  -v, --verbose           Verbose logging
  -h, --help              Show this help and exit

Example:
  run_rfantibody.sh \
    --framework inputs/framework/processed/vhh_HLT.pdb \
    --target inputs/target/3EAK_clean.pdb \
    --output-dir run_3EAK_001 \
    --design-loops "H1:7,H2:6,H3:5-13" \
    --hotspots "A123,A125,A130" \
    --n-designs 200 \
    --n-seqs 20 \
    --rf2-seed 42
EOF
}

die() {
  echo "ERROR: $*" >&2
  echo >&2
  usage >&2
  exit 1
}

# ============================================================================
# DEFAULT PARAMETERS
# ============================================================================

FRAMEWORK=""                        # To be parsed, RFAb expects fw in HLT format (generated from a Chothia-annotated PDB using ./scripts/util/chothia2HLT)
TARGET=""                           # To be parsed, target PDB
OUTPUTDIR="run_000"                 # name of the output directory. ex: "run_cd33_001" will write outputs in "${HOMEDIR}outputs/run_cd33_001/"

# RFdiffusion
N_DESIGNS=100                       # Number of designs to generate (def: 100 backbones)
DIFFUSER_T=50                       # RFdiff diffuser Timestep (def: 50)
DESIGN_LOOPS="H1:7,H2:6,H3:6-20"    # Loops to make (with or without lengths)
HOTSPOTS=""                         # Hotspot residues (target chain name + number)

# ProteinMPNN
N_SEQS=10                           # Seqs to generate per backbone
TEMP=0.2                            # ProteinMPNN temperature param

# RF2
N_RECYCLES=10                       # recycling steps (RF2)
RF2_SEED=""                         # Seed for reproducibility in RF2
HOTSPOT_PROP=0.1

# flags
DRY_RUN=false
VERBOSE=false
DETERMINISTIC=false                 # enable deterministic mode for rfdiff and proteinmpnn

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --framework)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      FRAMEWORK="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      TARGET="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      OUTPUTDIR="$2"
      shift 2
      ;;

    # RFdiffusion
    --n-designs)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      N_DESIGNS="$2"
      shift 2
      ;;
    --diffuser-t)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      DIFFUSER_T="$2"
      shift 2
      ;;
    --design-loops)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      DESIGN_LOOPS="$2"
      shift 2
      ;;
    --hotspots)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      HOTSPOTS="$2"
      shift 2
      ;;

    # ProteinMPNN
    --n-seqs)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      N_SEQS="$2"
      shift 2
      ;;
    --temp)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      TEMP="$2"
      shift 2
      ;;

    # RF2
    --n-recycles)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      N_RECYCLES="$2"
      shift 2
      ;;
    --rf2-seed)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      RF2_SEED="$2"
      shift 2
      ;;
    --hotspot-prop)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      HOTSPOT_PROP="$2"
      shift 2
      ;;

    # Other flags
    --dry-run)
      DRY_RUN=true
      shift 1
      ;;
    --deterministic)
      DETERMINISTIC=true
      shift 1
      ;;
    -v|--verbose)
      VERBOSE=true
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --) shift; break ;;
    -*) die "Unknown option: $1 (use --help)" ;;
    *)  die "Unexpected positional argument: $1 (use --help)" ;;
  esac
done

# ============================================================================
# REQUIRED ARGUMENT CHECKS
# ============================================================================

[[ -z "$FRAMEWORK" ]] && die "--framework is required"
[[ -z "$TARGET" ]]    && die "--target is required"
[[ -z "$OUTPUTDIR" ]] && die "--output-dir is required"

[[ ! -f "$FRAMEWORK" ]] && die "Framework file not found: $FRAMEWORK"
[[ ! -f "$TARGET" ]]    && die "Target file not found: $TARGET"


# ProteinMPNN parameter derived from the # of loops inputted into RFdiffusion
LOOPS=$(echo "$DESIGN_LOOPS" | sed 's/:[^,]*//g')

# ============================================================================
# OUTPUT LAYOUT + REPRODUCIBLE command.txt
# ============================================================================
# Path to RFantibody within ab-develop repo (ex: /user/username/ab-develop/projects/uc_denovo_vhh/RFantibody/)
echo $0
HOMEDIR="$(pwd)/../"
SCRIPTDIR="${HOMEDIR}/scripts/"
RUNDIR="${HOMEDIR}/outputs/${OUTPUTDIR}"
LOGDIR="${RUNDIR}/logs/"
mkdir -p "$RUNDIR"

# Reconstruct a reproducible command line (includes only non-defaults for brevity)
repro_cmd=( "$0"
  --framework "$FRAMEWORK"
  --target "$TARGET"
  --output-dir "$OUTPUTDIR"
)

# include non-defaults
[[ "$N_DESIGNS"    != "100" ]] && repro_cmd+=( --n-designs "$N_DESIGNS" )
[[ "$DIFFUSER_T"   != "50"  ]] && repro_cmd+=( --diffuser-t "$DIFFUSER_T" )
[[ "$DESIGN_LOOPS" != "H1:7,H2:6,H3:6-20" ]] && repro_cmd+=( --design-loops "$DESIGN_LOOPS" )
[[ -n "$HOTSPOTS" ]] && repro_cmd+=( --hotspots "$HOTSPOTS" )
[[ "$N_SEQS"       != "10"  ]] && repro_cmd+=( --n-seqs "$N_SEQS" )
[[ "$TEMP"         != "0.2" ]] && repro_cmd+=( --temp "$TEMP" )
[[ "$N_RECYCLES"   != "10"  ]] && repro_cmd+=( --n-recycles "$N_RECYCLES" )
[[ -n "$RF2_SEED" ]] && repro_cmd+=( --rf2-seed "$RF2_SEED" )
[[ "$HOTSPOT_PROP" != "0.1" ]] && repro_cmd+=( --hotspot-prop "$HOTSPOT_PROP" )
$DRY_RUN   && repro_cmd+=( --dry-run )
$VERBOSE   && repro_cmd+=( --verbose )

# Write command.txt with timestamp + resolved paths
{
  echo "# Generated: $(date -Is)"
  echo "# Run dir:   $RUNDIR"
  echo "# Host:      $(hostname)"
  echo "# PWD:       $HOMEDIR"
  echo
  printf '%q ' "${repro_cmd[@]}"
  echo
} > "${RUNDIR}/command.txt"

$VERBOSE && echo "Wrote ${RUNDIR}/command.txt"

# ============================================================================
# CONFIRMATION (optional)
# ============================================================================

$VERBOSE && {
  echo "FRAMEWORK      = $FRAMEWORK"
  echo "TARGET         = $TARGET"
  echo "OUTPUTDIR     = $OUTPUTDIR"
  echo "RUNDIR        = $RUNDIR"
  echo "N_DESIGNS      = $N_DESIGNS"
  echo "DIFFUSER_T     = $DIFFUSER_T"
  echo "DESIGN_LOOPS   = $DESIGN_LOOPS"
  echo "LOOPS          = $LOOPS"
  echo "HOTSPOTS       = $HOTSPOTS"
  echo "N_SEQS         = $N_SEQS"
  echo "TEMP           = $TEMP"
  echo "N_RECYCLES     = $N_RECYCLES"
  echo "RF2_SEED       = $RF2_SEED"
  echo "HOTSPOT_PROP   = $HOTSPOT_PROP"
  echo "DRY_RUN        = $DRY_RUN"
  echo "VERBOSE        = $VERBOSE"
}

# ============================================================================
# (rest of your pipeline goes here)
# Use: $RUNDIR as the root output path
# ============================================================================


# ============================================================================
# Running RFdiffusion
# ============================================================================

# For ease of use, run everything using quiver instead of pdbs

START_TIME="[$(date '+%Y-%m-%d %H:%M:%S')]"
echo "${START_TIME} Pipeline started"
source .venv/bin/activate

echo ""
echo "[Step 1/3] Running RFdiffusion"
echo "  - Generating $N_DESIGNS backbones"
echo "  - Loops: $DESIGN_LOOPS"
echo "  - Hotspots: $HOTSPOTS"

#rfdiffusion -t ${TARGET} -f ${FRAMEWORK} --output-quiver "${RUNDIR}/00_diffusion_backbones.qv" -n ${N_DESIGNS} -l ${DESIGN_LOOPS} -h ${HOTSPOTS} --diffuser-t ${DIFFUSER_T} > "${LOGDIR}/00_diffusion.log" 2>&1

echo "# ============================================================================"
echo "TESTING RFDIFF PARAMS"
echo " -t ${TARGET} -f ${FRAMEWORK} --output-quiver ${RUNDIR}/00_diffusion_backbones.qv -n ${N_DESIGNS} -l ${DESIGN_LOOPS} -h ${HOTSPOTS} --diffuser-t ${DIFFUSER_T} > ${LOGDIR}/00_diffusion.log"
echo "# ============================================================================"

echo "[Step 1/3] RFdiffusion complete"

# ============================================================================
# Running ProteinMPNN
# ============================================================================
echo ""
echo "[Step 2/3] Running ProteinMPNN"
echo "  - Generating $N_SEQS sequences per backbone"
echo "  - Sampling temperature: $TEMP"

#proteinmpnn --input-quiver "${RUNDIR}/00_diffusion.qv" --output-quiver "${RUNDIR}/01_pmpnn_sequences.qv" -l ${LOOPS} -n ${N_SEQS} > "${RUNDIR}/01_proteinmpnn_seq.log" 2>&1


echo "# ============================================================================"

echo "TESTING proteinmpnn PARAMS"
echo "proteinmpnn --input-quiver ${RUNDIR}/00_diffusion.qv --output-quiver ${RUNDIR}/01_pmpnn_sequences.qv -l ${LOOPS} -n ${N_SEQS} > ${RUNDIR}/01_proteinmpnn_seq.log"
echo "# ============================================================================"


echo "[Step 2/3] ProteinMPNN complete"


# ============================================================================
# Running RF2
# ============================================================================
echo ""
echo "[Step 3/3] Running RoseTTAFold2"
echo "  - Refining structures with $N_RECYCLES recycles"

#rf2 --input-quiver "${RUNDIR}/01_sequences.qv" --output-quiver "${RUNDIR}/02_rf2_predictions.qv" --hotspot-show-prop ${HOTSPOT_PROP} --num-recycles $N_RECYCLES > "${RUNDIR}/02_rf2_predictions.log" 2>&1
echo "# ============================================================================"

echo "TESTING proteinmpnn PARAMS"
echo "--input-quiver ${RUNDIR}/01_sequences.qv --output-quiver ${RUNDIR}/02_rf2_predictions.qv --hotspot-show-prop ${HOTSPOT_PROP} --num-recycles $N_RECYCLES > ${RUNDIR}/02_rf2_predictions.log"
echo "# ============================================================================"

echo "[Step 3/3] RF2 complete"

echo "=============================================="
echo "[All steps complete]"
echo "  - All outputs are saved at ${RUNDIR}"
echo "  - List backbones with:  uv run qvls ${RUNDIR}/00_diffusion_backbones.qv"
echo "  - List results with:    uv run qvls ${RUNDIR}/02_rf2_predictions.qv"
echo "  - Extract PDBs with:    uv run qvextract ${RUNDIR}/02_rf2_predictions.qv <output_dir>"
echo ""
echo "=============================================="

END_TIME="[$(date '+%Y-%m-%d %H:%M:%S')]"
echo "${END_TIME} Pipeline complete"
