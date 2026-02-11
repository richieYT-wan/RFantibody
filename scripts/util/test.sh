#!/bin/bash

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

conda activate ada
conda list | grep "dssp\|biopy"