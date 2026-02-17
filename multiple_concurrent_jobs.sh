#!/usr/bin/env bash
set -euo pipefail
#!/bin/bash

# Helper script to run multiple jobs in parallel on VertexAI when using multiple GPUs
# (assumes in the job definition that different --cuda-device have been set
# Ex: jobs that match the pattern "job_type_0" all have --cuda-device 0 in the run scripts

show_help() {
  echo "Usage: myscript.sh [PATTERN] [N_JOBS] [JOBDIR]"
  echo ""
  echo "Arguments:"
  echo "  PATTERN    e.g. quiver_7"
  echo "  N_JOBS     e.g. 5"
  echo "  JOBDIR     path/to/jobs/"
  echo ""
  echo "Options:"
  echo "  -h         Show this help message"
}

if [[ "$1" == "-h" || "$1" == "--help" || $# -eq 0 ]]; then
  show_help
  exit 0
fi

pattern="${1:?pattern required, e.g. quiver_7}"
NJOBS="${2:?n_jobs required, e.g. 5}"
JOBDIR="${3:?path/to/jobs/}"

# Ensure we are in RFantibody root (same logic)
ROOTDIR="$(pwd)"
if [[ "$(basename "$ROOTDIR")" != "RFantibody" ]]; then
  echo "Error: run this from RFantibody root" >&2
  exit 1
fi

find "$JOBDIR" -maxdepth 1 -type f -name "*.sh" -print0 \
  | xargs -0 -I{} basename "{}" \
  | grep -F "$pattern" \
  | sort \
  | sed "s|^|$JOBDIR/|" \
  | tr '\n' '\0' \
  | xargs -0 -n 1 -P $NJOBS bash

