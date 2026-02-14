#!/usr/bin/env bash
set -euo pipefail

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

