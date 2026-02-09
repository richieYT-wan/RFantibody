#!/bin/bash
set -euo pipefail  # Exit on error
HOMEDIR="${HOME}/RFantibody"
cd $HOMEDIR
source .venv/bin/activate

echo "${HOMEDIR} START HOME DIR HERE"
echo "[START $(date '+%Y-%m-%d %H:%M:%S')] Script started; Format: Quiver"

# ex usage: bash test_pipeline_pdb.sh /path/to/input/processed/framework_HLT.pdb /path/to/input/target/target.pdb "H1:7,H2:6,H3:5-13" "B146,B170,B177" 5 10 10
FRAMEWORK=""
TARGET=""
LOOPS="H1,H2,H3"
N_DESIGN=5
N_SEQUENCE=10
N_RECYCLE=10
HOTSPOTS=""
usage() {
  echo "Usage: $0 -f <framework.pdb> -t <target.pdb> -l <loops> -h <hotspots> -d <n_design> -s <n_sequence> -r <n_recycle>"
  exit 1
}

while getopts ":f:t:l:h:d:s:r:" opt; do
  case ${opt} in
    f )
      FRAMEWORK=$OPTARG ;;
    t )
      TARGET=$OPTARG ;;
    l )
      LOOPS=$OPTARG ;;
    h )
      HOTSPOTS=$OPTARG ;;
    d )
      N_DESIGN=$OPTARG ;;
    s )
      N_SEQUENCE=$OPTARG ;;
    r )
      N_RECYCLE=$OPTARG ;;
    *)
      usage ;;
  esac
done

FW_BN="$(basename "$FRAMEWORK")"
FW_BN="${FW_BN%.*}"
TG_BN="$(basename "$TARGET")"
TG_BN="${TG_BN%.*}"
NOW="$(date '+%Y%m%d_%H%M%S')"
FILENAME="${NOW}_TestRunQuiver_FW_${FW_BN}_TG_${TG_BN}"
OUTDIR="${HOMEDIR}/outputs/${FILENAME}"
LOGDIR="${HOMEDIR}/logs/${FILENAME}"
mkdir -p "${OUTDIR}" "${LOGDIR}"

echo "Running pipeline with: "
echo "$FRAMEWORK: input framework"
echo "$TARGET: input target"
echo "$LOOPS: Design loops"
echo "$HOTSPOTS: hotspots"
echo "$N_DESIGN: N designs (RFdiffusion)"
echo "$N_SEQUENCE: N sequences (ProteinMPNN)"
echo "$N_RECYCLE: N recycling steps (RF2)"

echo "******************"
echo "Starting pipeline"
echo "******************"
echo ""
echo "=============================================="
echo "Step 1/3: RFdiffusion with $N_DESIGN designs, $LOOPS Design Loops and $HOTSPOTS Hotspots"
echo "=============================================="
echo ""


HOTSPOT_ARGS=()

if [[ -n "$HOTSPOTS" ]]; then
  HOTSPOT_ARGS=(-h "$HOTSPOTS")
fi


rfdiffusion -f ${FRAMEWORK} -t ${TARGET} --output-quiver ${OUTDIR}/01_rfdiffusion.qv -n ${N_DESIGN} -l "${LOOPS}" --diffuser-t 50 ${HOTSPOT_ARGS[*]} > ${LOGDIR}/01_DIFFUSION.log 2>&1

echo ""
echo "=============================================="
echo "Step 2/3: ProteinMPNN with $N_SEQUENCE sequences"
echo "=============================================="
echo ""


proteinmpnn --input-quiver ${OUTDIR}/01_rfdiffusion.qv --output-quiver ${OUTDIR}/02_sequences.qv -l "H1,H2,H3" -n 10 > ${HOMEDIR}/logs/${FILENAME}_PROTEINMPNN.log


echo ""
echo "=============================================="
echo "Step 3/3: RF2 with $N_RECYCLE recycling steps"
echo "=============================================="
echo ""

rf2 --input-quiver ${OUTDIR}/02_sequences.qv --output-quiver ${OUTDIR}/03_RF2_folds.qv -r 10 > ${HOMEDIR}/logs/${FILENAME}_RF2.log 2>&1


echo "[END   $(date '+%Y-%m-%d %H:%M:%S')] Script finished FULL PDB"

echo "******************"
echo "Pipeline done"
echo "******************"

