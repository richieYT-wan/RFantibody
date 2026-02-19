#!/bin/bash
# Script to convert Chothia-formatted nanobody PDB files to HLT format
set -e # Exit on any error

# Utils thing here:
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Walk up until we find RFantibody
ROOTDIR="$SCRIPT_DIR"
while [[ "$ROOTDIR" != "/" && "$(basename "$ROOTDIR")" != "RFantibody" ]]; do
  ROOTDIR="$(dirname "$ROOTDIR")"
done

usage() {
  echo ""
  echo "Usage: $0 -f <INPUT_FILENAME> -h <HEAVYCHAIN> [-o <FULL_OUTPUT_PATH>]"
  echo "Example 1 (explicit output): $0 -f data/01_raw/framework/3eak_chothia.pdb -h A -o data/02_intermediate/framework/3eak_HLT.pdb"
  echo "Example 2 (automatic output): $0 -f data/01_raw/framework/3eak_chothia.pdb -h A"
  echo "  - INPUT_FILENAME: Path to the input Chothia PDB file."
  echo "  - HEAVYCHAIN: The chain ID to process (e.g., 'A')."
  echo "  - FULL_OUTPUT_PATH (optional): The complete path where the HLT PDB file should be saved."
  echo "    If not provided, output will be derived from input: e.g., 'data/01_raw/processed/3eak_HLT.pdb'"
  echo ""
  exit 1
}

# initialise variables
INPUT_FILENAME=""
HEAVYCHAIN=""
FULL_OUTPUT_PATH="" # This will store the final determined output path

while getopts ":f:o:h:" opt; do
  case ${opt} in
    f )
      INPUT_FILENAME=$OPTARG ;;
    o )
      FULL_OUTPUT_PATH=$OPTARG ;;
    h )
      HEAVYCHAIN=$OPTARG ;;
    *)
      usage ;;
  esac
done

# die if required arguments are missing
if [[ -z "$INPUT_FILENAME" || -z "$HEAVYCHAIN" ]]; then
  echo "Error: missing required arguments (-f and -h)"
  echo ""
  usage
fi

# If FULL_OUTPUT_PATH is not provided, generate it automatically
if [[ -z "$FULL_OUTPUT_PATH" ]]; then
  INPUT_DIR=$(dirname "${INPUT_FILENAME}")
  BASENAME=$(basename "${INPUT_FILENAME}")

  # Replace "_chothia" with "_HLT"
  DERIVED_BASENAME="${BASENAME/_chothia/_HLT}"

  # Ensure the extension is .pdb (if it was something else, this would fix it)
  # This also handles cases where _chothia might not be present, just appends _HLT
  if [[ "$DERIVED_BASENAME" != *.pdb ]]; then
    DERIVED_BASENAME="${DERIVED_BASENAME%.*}_HLT.pdb"
  fi

  # Determine the 'processed' directory one level up from INPUT_DIR
  # This assumes INPUT_DIR is like 'data/01_raw/framework'
  # and we want 'data/01_raw/processed'
  PARENT_DIR=$(dirname "$INPUT_DIR")
  AUTO_OUTPUT_DIR="${PARENT_DIR}/processed"

  FULL_OUTPUT_PATH="${AUTO_OUTPUT_DIR}/${DERIVED_BASENAME}"
fi

# Ensure the output directory exists
OUTPUT_DIR=$(dirname "${FULL_OUTPUT_PATH}")
mkdir -p "$OUTPUT_DIR"

echo "Converting input file ${INPUT_FILENAME} to HLT format"
echo "Saving output to ${FULL_OUTPUT_PATH}"
echo ""

source .venv/bin/activate

# Convert the nanobody file
echo "Converting nanobody file..."
python "$ROOTDIR/scripts/util/chothia2HLT.py" \
  "${INPUT_FILENAME}" \
  --heavy "$HEAVYCHAIN" \
  --output "${FULL_OUTPUT_PATH}"

echo "HLT conversion completed. File saved at ${FULL_OUTPUT_PATH}"
