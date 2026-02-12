#!/bin/bash
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
source .venv/bin/activate

echo "${ROOTDIR} START HOME DIR HERE"
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

while getopts ":f:t:l:h:d:s:r:c:" opt; do
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
    c )
      CUDA_DEVICE=$OPTARG ;;
    *)
      usage ;;
  esac
done

export CUDA_VISIBLE_DEVICES=$CUDA_DEVICE

FW_BN="$(basename "$FRAMEWORK")"
FW_BN="${FW_BN%.*}"
TG_BN="$(basename "$TARGET")"
TG_BN="${TG_BN%.*}"
NOW="$(date '+%y%m%d_%H%M%S')"
# Should include the hotspot in the filename here...
CLEAN_HOTSPOTS="${HOTSPOTS//,/}"
FILENAME="${NOW}_TestRunQuiver_Fw${FW_BN}_Tg${TG_BN}_Hs${CLEAN_HOTSPOTS}"
OUTDIR="${ROOTDIR}/outputs/${FILENAME}"
LOGDIR="${OUTDIR}/logs/"
mkdir -p "${OUTDIR}" "${LOGDIR}"

argslog() {
  echo ""
  echo "[START $(date '+%Y-%m-%d %H:%M:%S')] Script started; Format: PDB"
  echo ""
  echo "Running pipeline with: "
  echo "$FRAMEWORK: input framework"
  echo "$TARGET: input target"
  echo "$LOOPS: Design loops"
  echo "$HOTSPOTS: hotspots"
  echo "$N_DESIGN: N designs (RFdiffusion)"
  echo "$N_SEQUENCE: N sequences (ProteinMPNN)"
  echo "$N_RECYCLE: N recycling steps (RF2)"
}
argslog
argslog >> ${LOGDIR}/run.log

HOTSPOT_ARGS=()

if [[ -n "$HOTSPOTS" ]]; then
  HOTSPOT_ARGS=(-h "$HOTSPOTS")
fi

rfdlog() {
  echo "******************"
  echo "Starting pipeline"
  echo "******************"
  echo ""
  echo "=============================================="
  echo "Step 1/3: RFdiffusion with $N_DESIGN designs, $LOOPS Design Loops and $HOTSPOTS Hotspots"
  echo "=============================================="
  echo ""
  echo "rfdiffusion -f ${FRAMEWORK} -t ${TARGET} -o ${OUTDIR}/01_rfdiffusion.pdb -n ${N_DESIGN} -l ${LOOPS} --diffuser-t 50 ${HOTSPOT_ARGS[*]} > ${LOGDIR}/01_DIFFUSION.log 2>&1"
}
rfdlog
rfdlog >> ${LOGDIR}/run.log

rfdiffusion -f ${FRAMEWORK} -t ${TARGET} --output-quiver ${OUTDIR}/01_rfdiffusion.qv -n ${N_DESIGN} -l "${LOOPS}" --diffuser-t 50 ${HOTSPOT_ARGS[*]} > ${LOGDIR}/01_DIFFUSION.log 2>&1


pmpnnlog(){
  echo ""
  echo "=============================================="
  echo "Step 2/3: ProteinMPNN with $N_SEQUENCE sequences"
  echo "=============================================="
  echo ""
  echo "proteinmpnn -i ${OUTDIR}/01_rfdiffusion.pdb -o ${OUTDIR}/02_sequences.pdb -l "H1,H2,H3" -n ${N_SEQUENCE} > ${LOGDIR}/02_PROTEINMPNN.log 2>&1"
}
pmpnnlog
pmpnnlog >> ${LOGDIR}/run.log


proteinmpnn --input-quiver ${OUTDIR}/01_rfdiffusion.qv --output-quiver ${OUTDIR}/02_sequences.qv -l "H1,H2,H3" -n 10 > ${LOGDIR}/02_PROTEINMPNN.log 2>&1



rf2log(){
  echo ""
  echo "=============================================="
  echo "Step 3/3: RF2 with $N_RECYCLE recycling steps"
  echo "=============================================="
  echo ""
  echo "rf2 -i ${OUTDIR}/02_sequences.pdb -o ${OUTDIR}03_RF2_folds.pdb -r ${N_RECYCLE} > ${LOGDIR}/03_RF2.log 2>&1"
}
rf2log
rf2log >> ${LOGDIR}/run.log

rf2 --input-quiver ${OUTDIR}/02_sequences.qv --output-quiver ${OUTDIR}/03_RF2_folds.qv -r 10 > ${LOGDIR}/03_RF2.log 2>&1


endlog(){
  echo "[END   $(date '+%Y-%m-%d %H:%M:%S')] Script finished FULL PDB"
  echo "******************"
  echo "Pipeline done"
  echo "******************"
}
endlog
endlog >> ${LOGDIR}/run.log
