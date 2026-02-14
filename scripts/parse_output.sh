#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Walk up until we find RFantibody; need this path for source .venv/bin/activate
ROOT_DIR="$SCRIPT_DIR"
while [[ "$ROOT_DIR" != "/" && "$(basename "$ROOT_DIR")" != "RFantibody" ]]; do
  ROOT_DIR="$(dirname "$ROOT_DIR")"
done

if [[ "$(basename "$ROOT_DIR")" != "RFantibody" ]]; then
  echo "Error: Could not locate RFantibody root directory."
  exit 1
fi

source ~/.bashrc
conda activate ada
# Stupid python fix for Workstation
PYTHON="$(which python)"

usage() {
  cat <<'EOF'
Usage:
  parse_output.sh -i PATH --format {pdb|qv} [-o OUTFILE]

Args:
  -i, --results_path PATH   Input directory (pdb) OR .qv file (qv)
  --format {pdb|qv}         Input type
  -o, --outfile FILE        Output table (default: parsed_outputs.tsv)
EOF
}

die() { echo "ERROR: $*" >&2; usage >&2; exit 1; }

RESULTS_PATH=""
FORMAT=""
OUTFILE="parsed_outputs.csv"
N_JOBS=-1
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--results_path) RESULTS_PATH="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -o|--outfile) OUTFILE="$2"; shift 2 ;;
    --n-jobs) N_JOBS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -z "$RESULTS_PATH" ]] && die "Missing -i/--results_path"
[[ -z "$FORMAT" ]] && die "Missing --format"
[[ "$FORMAT" == "pdb" || "$FORMAT" == "qv" ]] || die "Invalid --format '$FORMAT' (must be pdb|qv)"

# ------------------------------------------------------------------
# Resolve PDB_DIR and (optional) SCORES_PATH
# ------------------------------------------------------------------
PDB_DIR=""
SCORES_PATH=""

RES_DIR="$(cd "$(dirname "$RESULTS_PATH")" && pwd)"
ORIG_FILENAME="$(basename ${RES_DIR})"
echo "$ORIG_FILENAME"
OUTFILE="${RES_DIR}/${OUTFILE}"
if [[ "$FORMAT" == "qv" ]]; then
  # Go to the rootdir and activate to get the right venv to run qv commands
  cd $ROOT_DIR
  source .venv/bin/activate

  command -v qvextract   >/dev/null || die "qvextract not found"
  command -v qvscorefile >/dev/null || die "qvscorefile not found"

  [[ -f "$RESULTS_PATH" ]] || die "QV file not found: $RESULTS_PATH"

  RES_DIR="$(cd "$(dirname "$RESULTS_PATH")" && pwd)"
  QV_BN="$(basename "$RESULTS_PATH")"
  EXTRACT_DIR="$RES_DIR/extracted_pdbs"
  mkdir -p "$EXTRACT_DIR"

  echo "Extracting PDBs from QV -> $EXTRACT_DIR"
  qvextract "$RESULTS_PATH" -o "$EXTRACT_DIR" # --force

  # qvscorefile writes outputs relative to where it is called
  echo "Scoring QV -> ${QV_BN%.*}.sc"
  ( cd "$RES_DIR" && qvscorefile "$QV_BN" )

  # Take the outputted .sc file that contains the tsv scores
  SCORES_PATH="$RES_DIR/${QV_BN%.*}.sc"
  [[ -f "$SCORES_PATH" ]] || die "Expected score file not found: $SCORES_PATH"

  PDB_DIR="$EXTRACT_DIR"
  # Here call a python script to handle the output parsing and CSV generation
  echo "Running python parsing script and saving results"
  # Original filename is used to parse settings (from auto naming in pipeline_rfantibody or custom job name)
  $PYTHON "${ROOT_DIR}/scripts/util/parse_output.py" --original_filename $ORIG_FILENAME --pdb-dir "$PDB_DIR" --scores "$SCORES_PATH" -o "$OUTFILE" --n_jobs $N_JOBS

else
  [[ -d "$RESULTS_PATH" ]] || die "PDB directory not found: $RESULTS_PATH"
  PDB_DIR="$(cd "$RESULTS_PATH" && pwd)"
  echo "Running python parsing script and saving results"
  $PYTHON "${ROOT_DIR}/scripts/util/parse_output.py" --original_filename $ORIG_FILENAME --pdb-dir "$PDB_DIR" -o "$OUTFILE"--n_jobs $N_JOBS
fi

echo "Saved output CSV table at $OUTFILE"
