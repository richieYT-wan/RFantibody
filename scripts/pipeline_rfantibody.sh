#!/bin/bash

# ============================================================================
# Full Nanobody Design Pipeline
# ============================================================================
# This script runs the complete nanobody design workflow:
#   1. RFdiffusion  - Design nanobody backbone structures
#   2. ProteinMPNN  - Design sequences for the backbones
#   3. RF2          - Predict/refine final structures
# Usage: bash /scripts/pipeline_rfantibody.sh
# ============================================================================

set -euo pipefail  # Exit on error
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Walk up until we find RFantibody
ROOT_DIR="$SCRIPT_DIR"
while [[ "$ROOT_DIR" != "/" && "$(basename "$ROOT_DIR")" != "RFantibody" ]]; do
  ROOT_DIR="$(dirname "$ROOT_DIR")"
done

if [[ "$(basename "$ROOT_DIR")" != "RFantibody" ]]; then
  echo "Error: Could not locate RFantibody root directory."
  exit 1
fi

source .venv/bin/activate

# ============================================================================
# INPUT PARAMETERS // ARGUMENT PARSING DEFINITION
# ============================================================================


# RFdiffusion parameters
FRAMEWORK=""                               # TO BE PARSED required; RFAntibody expects frameworks in "HLT" format
                                           # created using from a Chothia-annotated PDB using
                                           # ./scripts/util/convert_chothia2hlt_antibody.sh
TARGET=""                                 # TO BE PARSED required;
                                           # created using from a RCSB PDB using
                                           # ./scripts/util/pipeline_clean_target.sh
OUTPUT_NAME=""                             # a custom name of the run directory. ex: "run_cd33_001" will
                                           # write outputs in "<ROOT_DIR>/outputs/<TIMESTAMP>_run_cd33_001/ (default: autogenerates a timestamp and name based on inputs (framework, target, hotspot))
N_DESIGN=25                               # Number of designs to generate (default: 100 backbones)
DIFFUSER_T=50                              # Diffusion time-steps (default: 50)
DESIGN_LOOPS="H1:,H2:,H3:"                    # Loops to design with or without length;
                                           # ex: "H1:7,H2:6,H3:5-13" to make H1,H2,H3 loops with lengths 7, 6 and ranging 5 to 13
HOTSPOTS=""                                # Hotspot residues on target, uses the target chain identifier;
                                           # ex: "A149,A151,A154" (empty means not used)

# ProteinMPNN parameters ; missing : --augment-eps FLOAT --> backbone noise augmentation
LOOPS=$(echo "$DESIGN_LOOPS" | sed 's/:[^,]*//g') # Parses the DESIGN_LOOPS and removes lengths
N_SEQUENCE=10                                  # Number of sequences to generate per backbone (default: 10 seqs / backbone)
TEMP=0.2                                   # ProteinMPNN sampling temp (default: 0.2)


# RF2 parameters ;
N_RECYCLE=10                              # Number of recycling steps in RF2 (default: 10)
RF2_SEED=""                                # RF2 seed for reproducibility (Optional: int, empty means do not use)
HOTSPOT_PROP=0.1                           # Proportion of hotspot residues to show to model (default: 0.1)

# Other flags ?
FORMAT="qv"                                # format to use for inputs/outputs (qv or pdb)
CUDA_DEVICE=0                              # which cuda gpu to use (default: 0, int)

die() {
  echo "ERROR: $*" >&2
  echo >&2
  usage >&2
  exit 1
}


# ============================================================================
# ARGUMENT PARSING
# ============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") -f FRAMEWORK -t TARGET [OPTIONS]

Full Nanobody Design Pipeline using RFdiffusion, ProteinMPNN, and RF2.

Required Arguments:
  -f, --framework FILE      Path to framework file (HLT format)
  -t, --target FILE         Path to target file (cleaned PDB format from script)

Misc. Arguments:
  -o, --output-name STR     Custom name for the run directory (default: auto)
  -c, --cuda-device INT     Custom cuda device (default: 0)

RFdiffusion Options:
  --n-designs INT           Number of backbones to generate (default: 25)
  --diffuser-t INT          Diffusion time-steps (default: 50)
  --design-loops STR        Loops and lengths to design (e.g., "H1:7,H2:6,H3:5-13" or "H1:,H2:,H3:")
  --hotspots STR            Target hotspots (e.g., "A149,A150,A151")

ProteinMPNN Options:
  --n-seqs INT              Sequences per backbone (default: 10)
  --temp FLOAT              Sampling temperature (default: 0.2)

RF2 Options:
  --n-recycles INT          Number of recycling steps (default: 10)
  --rf2-seed INT            Seed for reproducibility
  --hotspot-prop FLOAT      Proportion of hotspots shown to model (default: 0.1)

Other Options:
  --format STR              Input/output format: qv or pdb (default: qv)
  --cuda-device INT         GPU device ID (default: 0)
  -h, --help                Show this help message
EOF
}

repro_cmd_exact=( "$0" "$@" )

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f | --framework)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      FRAMEWORK="$2"
      shift 2
      ;;
    -t | --target)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      TARGET="$2"
      shift 2
      ;;
    -o | --output-name)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      OUTPUT_NAME="$2"
      shift 2
      ;;

    # RFdiffusion
    --n-designs)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      N_DESIGN="$2"
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
      N_SEQUENCE="$2"
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
      N_RECYCLE="$2"
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
    --format)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      [[ $2 == "pdb" || $2 == "qv" ]] || { echo "Invalid --format $2. Must be qv or pdb"; die; }
      FORMAT="$2"
      shift 2
      ;;
    -c|--cuda-device)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      CUDA_DEVICE="$2"
      shift 2
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
[[ ! -f "$FRAMEWORK" ]] && die "Framework file not found: $FRAMEWORK"
[[ ! -f "$TARGET" ]]    && die "Target file not found: $TARGET"

# Set CUDA device:
export CUDA_VISIBLE_DEVICES=$CUDA_DEVICE

# ============================================================================
# PATHS SETTING AND OUTPUT LAYOUT + REPRODUCIBLE command.txt
# ============================================================================
# Create the output directory for the run
NOW="$(date '+%y%m%d_%H%M%S')"
# If no custom output name is provided, create it based on the input framework, target and hotspot as minimal identifier
if [[ ! -n $OUTPUT_NAME ]]; then
  FW_BN="$(basename "$FRAMEWORK")"
  FW_BN="${FW_BN%.*}"
  TG_BN="$(basename "$TARGET")"
  TG_BN="${TG_BN%.*}"
  # Should include the hotspot in the filename here...
  CLEAN_HOTSPOTS="${HOTSPOTS//,/}"
  FILENAME="${NOW}_run${FORMAT}_fw${FW_BN}_tg${TG_BN}_hs${CLEAN_HOTSPOTS}"
else
  FILENAME="${NOW}_${OUTPUT_NAME}"
fi
SCRIPT_DIR="${ROOT_DIR}/scripts"
OUTPUT_DIR="${ROOT_DIR}/outputs/${FILENAME}"
LOGS_DIR="${OUTPUT_DIR}/logs"
mkdir -p "${OUTPUT_DIR}" "${LOGS_DIR}"

# Write command.txt with timestamp + resolved paths
{
  echo "# Generated: $(date -Is)"
  echo "# Run dir:   ${OUTPUT_DIR}"
  echo "# Host:      $(hostname)"
  echo "# PWD:       ${ROOT_DIR}"
  echo
  printf '%q ' "${repro_cmd_exact[@]}"
  echo
} > "${LOGS_DIR}/command.txt"

echo "Wrote ${LOGS_DIR}/command.txt"


# ============================================================================
# Args handling and commands creation + running
# ============================================================================

# Generate hotspot and loops args
HOTSPOT_ARGS=()
if [[ -n "$HOTSPOTS" ]]; then
  HOTSPOT_ARGS=(-h "$HOTSPOTS")
fi


# ProteinMPNN parameter derived from the # of loops inputted into RFdiffusion
LOOPS=$(echo "$DESIGN_LOOPS" | sed 's/:[^,]*//g')

# Different format handling
if [[ $FORMAT == "qv" ]]; then
  RFDIFF_CMD="rfdiffusion -f ${FRAMEWORK} -t ${TARGET} --output-quiver ${OUTPUT_DIR}/01_rfdiffusion.qv -n ${N_DESIGN} -l ${DESIGN_LOOPS} --diffuser-t ${DIFFUSER_T} ${HOTSPOT_ARGS[*]}"
  
  PROTEINMPNN_CMD="proteinmpnn --input-quiver ${OUTPUT_DIR}/01_rfdiffusion.qv --output-quiver ${OUTPUT_DIR}/02_sequences.qv -l ${LOOPS} -n ${N_SEQUENCE}"
  
  RF2_CMD="rf2 --input-quiver ${OUTPUT_DIR}/02_sequences.qv --output-quiver ${OUTPUT_DIR}/03_RF2_folds.qv -r ${N_RECYCLE}"
  
elif [[ $FORMAT == "pdb" ]]; then
  RFDIFF_CMD="rfdiffusion -f ${FRAMEWORK} -t ${TARGET} -o ${OUTPUT_DIR}/01_rfdiffusion/design -n ${N_DESIGN} -l ${DESIGN_LOOPS} --diffuser-t ${DIFFUSER_T} ${HOTSPOT_ARGS[*]}"
  
  PROTEINMPNN_CMD="proteinmpnn -i ${OUTPUT_DIR}/01_rfdiffusion/ -o ${OUTPUT_DIR}/02_sequences/ -l ${LOOPS} -n ${N_SEQUENCE}"
  
  RF2_CMD="rf2 -i ${OUTPUT_DIR}/02_sequences/ -o ${OUTPUT_DIR}/03_RF2_folds/ -r ${N_RECYCLE}"
fi

START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

rfdlog() {
  echo "[START $START_TIME] Script started; Format: PDB"
  echo ""
  echo "******************"
  echo "Starting pipeline"
  echo "******************"
  echo ""
  echo "=============================================="
  echo "Step 1/3: RFdiffusion with $N_DESIGN designs, $DESIGN_LOOPS Design Loops and $HOTSPOTS Hotspots"
  echo "=============================================="
  echo ""
  echo $RFDIFF_CMD
}
rfdlog >> "${LOGS_DIR}/run.log"

$RFDIFF_CMD > ${LOGS_DIR}/01_DIFFUSION.log 2>&1

pmpnnlog(){
  echo ""
  echo "=============================================="
  echo "Step 2/3: ProteinMPNN with $N_SEQUENCE sequences"
  echo "=============================================="
  echo ""
  echo $PROTEINMPNN_CMD
}
pmpnnlog
pmpnnlog >> "${LOGS_DIR}/run.log"

$PROTEINMPNN_CMD > ${LOGS_DIR}/02_PROTEINMPNN.log 2>&1

rf2log(){
  echo ""
  echo "=============================================="
  echo "Step 3/3: RF2 with $N_RECYCLE recycling steps"
  echo "=============================================="
  echo ""
  echo $RF2_CMD
}
rf2log
rf2log >> "${LOGS_DIR}/run.log"

$RF2_CMD > ${LOGS_DIR}/03_RF2.log 2>&1

END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
endlog(){
    echo ""
    echo "******************"
    echo "Pipeline done"
    echo "******************"
    echo ""
    echo "[END   $END_TIME] Script finished in $FORMAT"
}
endlog
endlog >> "${LOGS_DIR}/run.log"

