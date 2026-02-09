#!/bin/bash

# Runs a full pipeline for the example nanobody scaffold, using the quiver formats
set -euo pipefail  # Exit on error
HOMEDIR="${HOME}/ab-develop/projects/uc_denovo_vhh/RFantibody/"
cd $HOMEDIR
source .venv/bin/activate
# TODO: REMOVE THIS
echo "${HOMEDIR} START HOME DIR HERE"
echo "[START $(date '+%Y-%m-%d %H:%M:%S')] Script started QUIVER"
FILENAME="QV_RUN_${1}"

rfdiffusion -t ${HOMEDIR}scripts/examples/example_inputs/flu_HA.pdb -f ${HOMEDIR}scripts/examples/example_inputs/h-NbBCII10.pdb --output-quiver ${HOMEDIR}scripts/examples/testrun_outputs/quiver_outputs/${FILENAME}designs.qv -n 5 -l "H1:7,H2:6,H3:5-13" -h "B146,B170,B177" --diffuser-t 25 > ${HOMEDIR}logs/${FILENAME}_DIFFUSION.log 2>&1

proteinmpnn --input-quiver ${HOMEDIR}scripts/examples/testrun_outputs/quiver_outputs/${FILENAME}designs.qv --output-quiver ${HOMEDIR}/scripts/examples/testrun_outputs/quiver_outputs/${FILENAME}sequences.qv -l "H1,H2,H3" -n 10 > ${HOMEDIR}/logs/${FILENAME}_PROTEINMPNN.log


rf2 --input-quiver ${HOMEDIR}scripts/examples/testrun_outputs/quiver_outputs/${FILENAME}sequences.qv --output-quiver ${HOMEDIR}scripts/examples/testrun_outputs/quiver_outputs/${FILENAME}predictions.qv -r 10 > ${HOMEDIR}/logs/${FILENAME}_RF2.log 2>&1

echo "[END   $(date '+%Y-%m-%d %H:%M:%S')] Script finished QUIVER"
