#!/bin/bash


# This script runs the pipeline to clean the target PDB and runs DSSP on it to extract (and add to REMARKs) surface accessible residues
set -euo pipefail # Exit on error

# SCRIPT PATH FINDING ;
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

echo "Starting $0 script in $ROOTDIR"

# CONDA FINDING HOTFIX ;
# Fixing conda initialisation errors...
ensure_conda() {
  # 1) already available (function or executable)?
  if type conda >/dev/null 2>&1; then
    return 0
  fi

  # 2) Try Windows Git Bash: conda.exe hook
  if command -v conda.exe >/dev/null 2>&1; then
    eval "$(conda.exe shell.bash hook)"
    type conda >/dev/null 2>&1 && return 0
  fi

  # 3) Try Linux/macOS: conda shell hook (if conda executable exists)
  if command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
    type conda >/dev/null 2>&1 && return 0
  fi

  # 4) Source typical conda.sh locations (no user-specific hard-coding)
  for csh in \
    "$HOME/miniconda3/etc/profile.d/conda.sh" \
    "$HOME/anaconda3/etc/profile.d/conda.sh" \
    "$HOME/mambaforge/etc/profile.d/conda.sh" \
    "/opt/conda/etc/profile.d/conda.sh" \
    "/usr/local/miniconda3/etc/profile.d/conda.sh" \
    "/usr/local/anaconda3/etc/profile.d/conda.sh"
  do
    if [[ -f "$csh" ]]; then
      # shellcheck disable=SC1090
      source "$csh"
      type conda >/dev/null 2>&1 && return 0
    fi
  done

  # 5) As a last resort, source interactive init files (some setups only init conda there)
  for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [[ -f "$rc" ]]; then
      # shellcheck disable=SC1090
      source "$rc"
      type conda >/dev/null 2>&1 && return 0
    fi
  done

  echo "Error: conda not found/initialised in this shell."
  echo "Hint: ensure your conda install is available or source conda.sh before running scripts."
  return 1
}
ensure_conda || exit 1
# --- Initialise conda for non-interactive shell ---
if ! type conda >/dev/null 2>&1; then
  echo "Error: conda executable not found in PATH."
  exit 1
fi

# Initialise shell integration activate environment
eval "$(conda shell.bash hook)"
conda activate ada

usage() {
  cat <<EOF
Usage:
  $0 -i|--input_file <input_file> -o|--output_file <output_file> [options]

Required:
  -i, --input_file        Input PDB file path
  -o, --output_file       Output file path

Optional:
      --chains <A,B>      Chains to keep (comma-separated)
      --ligands <NAG,FVP> Ligand residue names (comma-separated)
      --cutoff <float>    Ligand occlusion cutoff in Å (default: 4.0)
      --threshold <float> RSA threshold for hotspot suggestion (default: 0.2)
      --run_dssp          Run DSSP before cleaning (required if using RSA threshold)
      --renumber          Renumber residues (default: off)
      --help              Show this help message

Example:
  $0 -i inputs/target/raw/CD33_7AW6.pdb -o inputs/target/processed/CD33_7AW6_processed.pdb --chains A,B --ligands NAG,FVP --run_dssp --renumber

EOF
  exit 1
}

INPUT_PDB=""
OUTPUT_NAME=""
PDB_ID=""
CHAINS=""
LIGANDS=""
CUTOFF_ANGSTROM=4.0
THRESHOLD_RSA=0.2
RUN_DSSP=""
RENUMBER=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--input_file)
      [[ $# -ge 2 ]] || usage
      INPUT_PDB="$2"
      shift 2
      ;;
    -o|--output_file)
      [[ $# -ge 2 ]] || usage
      OUTPUT_NAME="$2"
      shift 2
      ;;
    --chains)
      [[ $# -ge 2 ]] || usage
      CHAINS="$2"
      shift 2
      ;;
    --cutoff)
      [[ $# -ge 2 ]] || usage
      CUTOFF_ANGSTROM="$2"
      shift 2
      ;;
    --threshold)
      [[ $# -ge 2 ]] || usage
      THRESHOLD_RSA="$2"
      shift 2
      ;;
    --ligands)
      [[ $# -ge 2 ]] || usage
      LIGANDS="$2"
      shift 2
      ;;
    --run_dssp)
      RUN_DSSP=true
      shift
      ;;
    --renumber)
      RENUMBER=true
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Argument checks for input file
if [[ -z "$INPUT_PDB" ]]; then
  echo "Error: -i|--input_file is required."
  usage
fi

if [[ -z "$OUTPUT_NAME" ]]; then
  echo "Error: -o|--output_file is required."
  usage
fi

if [[ ! -f "$INPUT_PDB" ]]; then
  echo "Error: File not found: $INPUT_PDB"
  exit 1
fi


# Adding extra arguments for clean target script based on flags
CLEANPDB_PYARGS=()
if $RENUMBER; then
  CLEANPDB_PYARGS+=( --renumber)
fi

CHAIN_ARGS=()
if [[ -n $CHAINS ]]; then
  CHAIN_ARGS+=( --chains "$CHAINS")
fi

# Optional: runs DSSP
if $RUN_DSSP; then
  OUTPUT_DSSP=${INPUT_PDB%.*}_dssp.csv
  echo "Running DSSP on $INPUT_PDB"
  python ./scripts/util/run_dssp.py -i $INPUT_PDB --which_dssp mkdssp "${CHAIN_ARGS[@]}"
  CLEANPDB_PYARGS+=( --dssp_csv $OUTPUT_DSSP --rsa_threshold $THRESHOLD_RSA)
fi

echo "Cleaning PDB file $INPUT_PDB"

python ./scripts/util/clean_target_pdb.py -i $INPUT_PDB -o ${OUTPUT_NAME} --ligands $LIGANDS --cutoff $CUTOFF_ANGSTROM "${CLEANPDB_PYARGS[@]}" "${CHAIN_ARGS[@]}"

if [[ -n "$CHAINS" ]]; then
  CHAINS_UNDERSCORE="$(echo "$CHAINS" | tr ',' '_')"
  OUTPUT_NAME="${OUTPUT_NAME%.*}_chains_${CHAINS_UNDERSCORE}.${OUTPUT_NAME##*.}"
fi


echo "Cleaning complete; Saving output at ${OUTPUT_NAME}"