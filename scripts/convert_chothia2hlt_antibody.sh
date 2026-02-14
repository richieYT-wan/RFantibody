#!/bin/bash

# Script to convert Chothia-formatted antibody PDB files to HLT format

set -e  # Exit on any error

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
  echo "Usage: $0 -f <FILENAME> -h <heavychain> -o <custom_output_name>"
  echo "Example: $0 -f path/to/file_chothia.pdb -h A -o custom_name.pdb"
  echo "  - process chain A from /path/to/raw/file_chothia.pdb"
  echo "  - save the result in either"
  echo "    /path/to/processed/file_HLT.pdb"
  echo "    or"
  echo "    /path/to/processed/custom_name.pdb if the -o flag is used. Do not provide the extension in
  the custom name."
  echo "Use relative paths to input and output dir, assuming you run this script from the root (<...>/RFantibody/)"
  echo ""
  exit 1
}


# initialise variables
FILENAME=""
OUTPUT=""
HEAVYCHAIN=""
LIGHTCHAIN=""
HEAVYCROP=113 # Chain cropping at # residue
LIGHTCROP=107 # Chain cropping at # residue
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--file)
      FILENAME="$2"
      shift 2 # Shift 2 to past argument & value
      ;;
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    -h|--heavy)
      HEAVYCHAIN="$2"
      shift 2
      ;;
    -l|--light)
      LIGHTCHAIN="$2"
      shift 2
      ;;
    -lc|--light-crop)
      LIGHTCROP="$2"
      shift 2
      ;;
    -hc|--heavy-crop)
      HEAVYCROP="$2"
      shift 2
      ;;
    --)
      shift
      break
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

# die if required arguments are missing
if [[ -z "$FILENAME" || -z "$HEAVYCHAIN" || -z "$LIGHTCHAIN" ]]; then
  echo "Error: missing required arguments"
  echo ""
  usage
fi

# Filename handling if no custom name is provided
if [[ -z "$OUTPUT" ]]; then
  # File paths and renaming
  INPUT_DIR="$(dirname "${FILENAME}")"
  BASENAME="$(basename "${FILENAME}")"
  if [[ "$BASENAME" == *chothia* ]]; then
    OUTPUT="${BASENAME/chothia/HLT}"
  else
    base="${BASENAME%.*}"
    ext="${BASENAME##*.}"
    OUTPUT="${base}_HLT.${ext}"
  fi
  OUTPUT="${OUTPUT%.*}"
fi

# Saving outputs one path up relative to the input file and into an "HLT" directory and renames it with _HLT extension
TMP="${ROOTDIR}${INPUT_DIR}/"
OUTPUT_DIR="$(cd "$TMP/../" && pwd)/processed"
mkdir -p "$OUTPUT_DIR"

echo "Converting input file ${FILENAME} to HLT format"
echo "Saving output to "${OUTPUT_DIR}/${OUTPUT}.pdb""
echo ""

# Convert the antibody file
echo "Converting antibody file..."
python "$ROOTDIR/scripts/util/chothia2HLT.py" \
  "${FILENAME}" \
  --heavy $HEAVYCHAIN \
  --light $LIGHTCHAIN \
  --Hcrop $HEAVYCROP \
  --Lcrop $LIGHTCROP \
  --output "${OUTPUT_DIR}/${OUTPUT}.pdb"

echo "HLT conversion completed."