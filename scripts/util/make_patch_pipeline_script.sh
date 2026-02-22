#!/usr/bin/env bash
set -euo pipefail

# Define rootdir
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Walk up until we find RFantibody
ROOT_DIR="$SCRIPT_DIR"
while [[ "$ROOT_DIR" != "/" && "$(basename "$ROOT_DIR")" != "RFantibody" ]]; do
  ROOT_DIR="$(dirname "$ROOT_DIR")"
done

usage() {
  cat << 'EOF'
Usage:
  script.sh [OPTIONS]

Required arguments:
  -f, --framework PATH        Path to framework PDB (Chothia annotated)
  -t, --target PATH           Path to target PDB
  -T, --threshold FLOAT       summed RSA Threshold value 

Optional arguments:
  -S, --start-spec STR        Start specification (default: unset)
  -c, --cuda INT              CUDA device ID
  -d, --n-designs INT         Number of designs to generate
  -s, --n-seqs INT            Number of sequences
  -r, --n-recycles INT        Number of recycles
  -L, --design-loops STR      Loop design specification
  -O, --jobs-dir DIR          Output jobs directory
  -R, --results-dir DIR       Results saving directory (default: auto)

Help:
  -h, --help                  Show this help message and exit

Examples:
  script.sh -f fw.pdb -t target.pdb --n-designs 50
  script.sh --framework fw.pdb --target target.pdb --cuda 0

Patch criteria:
- same chain
- residues increasing
- gaps: (r2-r1)<=2 and (r3-r2)<=2
- RSA sum: rsa(r1)+rsa(r2)+rsa(r3) >= THRESHOLD
- optional start filter: ignore residues before CHAINSTART (e.g. A148) on that chain only
EOF
  exit 2
}

framework=""
target=""
start_spec=""
threshold=""
CUDA=0
CUSTOM_NAME=""
N_DESIGNS=10
N_SEQS=10
N_RECYCLES=10
DESIGN_LOOPS="H1:7,H2:5-7,H3:6-18"
JOBS_DIR="" 
RESULTS_DIR=""
# TODO: Refactor and make it handle flags a bit more explicitly
#       Add the option to give jobs custom names (reflected in both the script AND the --output name in the pipeline_rfantibody call)
#       Keep the Hotspot naming convention ? --> Don't give custom name in the --output maybe to save the info in naming convention
# --- long/short option parsing (GNU-style) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--framework)
      framework="$2"; shift 2 ;;
    -t|--target)
      target="$2"; shift 2 ;;
    -S|--start-spec)
      start_spec="$2"; shift 2 ;;
    -T|--threshold)
      threshold="$2"; shift 2 ;;
    -c|--cuda)
      CUDA="$2"; shift 2 ;;
    -d|--n-designs)
      N_DESIGNS="$2"; shift 2 ;;
    -s|--n-seqs)
      N_SEQS="$2"; shift 2 ;;
    -r|--n-recycles)
      N_RECYCLES="$2"; shift 2 ;;
    -L|--design-loops)
      DESIGN_LOOPS="$2"; shift 2 ;;
    -O|--jobs-dir)
      JOBS_DIR="$2"; shift 2 ;;
    -R|--results-dir)
      RESULTS_DIR="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      echo "" 
      echo "Unknown option: $1; Exiting" >&2
      echo "" 
      usage | grep "Help:" -B 99 -A 1; exit 1 ;;
    *)
      break ;;
  esac
done

# Require args
[[ -n "$framework" ]] || { echo "Framework is required!" >&2; echo ""; usage; }
[[ -n "$target"    ]] || { echo "Target is required!" >&2; echo ""; usage; }
[[ -n "$threshold" ]] || { echo "Threshold is required!" >&2; echo ""; usage; }
[[ -f "$framework" ]] || { echo "ERROR: framework not found: $framework" >&2; exit 2; }
[[ -f "$target"    ]] || { echo "ERROR: target not found: $target" >&2; exit 2; }

# validate threshold is numeric
gawk -v T="$threshold" 'BEGIN{ if (T+0 != T) exit 1 }' || { echo "ERROR: -T must be numeric (e.g. 1.5)" >&2; exit 2; }
if [[ -z "${JOBS_DIR}" ]]; then
  JOBS_DIR="${ROOT_DIR}/scripts/rfantibody_jobs"
fi
LOGDIR="$(realpath -m "$JOBS_DIR/logs")"
mkdir -p "$JOBS_DIR" "$LOGDIR"

# basenames without extensions
fw_base="$(basename "$framework")"; fw_base="${fw_base%.*}"
tg_base="$(basename "$target")";    tg_base="${tg_base%.*}"

sanitize() {
  printf "%s" "$1" \
  | sed -E 's/[^A-Za-z0-9._-]+/_/g; s/^_+//; s/_+$//; s/_+/_/g'
}

fw_tag="$(sanitize "$fw_base")"
tg_tag="$(sanitize "$tg_base")"

# ---- Find patches from REMARK 900 hotspot lines, with RSA filtering ----
patches="$(
gawk -v START_SPEC="$start_spec" -v THRESHOLD="$threshold" '
  BEGIN {
    if (START_SPEC != "") {
      if (match(START_SPEC, /^([A-Za-z])([0-9]+)$/, m)) {
        start_chain = m[1]
        start_res   = m[2] + 0
        has_start   = 1
      } else {
        print "ERROR: start spec must look like A148" > "/dev/stderr"
        exit 2
      }
    } else {
      has_start = 0
    }
  }

  # Match lines like:
  # REMARK 900 P A150 rsa=0.4706 asa=64.00
  $1=="REMARK" && $2=="900" && $3 ~ /^[A-Z]$/ && $4 ~ /^[A-Za-z][0-9]+/ {
    chain = substr($4, 1, 1)
    res   = substr($4, 2) + 0

    if (has_start && chain == start_chain && res < start_res) next

    # Extract rsa=...
    rsa = ""
    if (match($0, /rsa=([0-9]*\.[0-9]+|[0-9]+)/, rm)) {
      rsa = rm[1] + 0.0
    } else {
      next
    }

    key = chain SUBSEP res
    if (!seen[key]++) {
      count[chain]++
      arr[chain, count[chain]] = res
    }
    rsa_map[chain, res] = rsa
  }

  END {
    for (chain in count) {
      n = count[chain]

      delete tmp
      for (i=1; i<=n; i++) tmp[i] = arr[chain, i]

      delete ord
      asorti(tmp, ord, "@val_num_asc")

      delete reslist
      for (i=1; i<=n; i++) reslist[i] = tmp[ ord[i] ]

      for (i=1; i<=n-2; i++) {
        r1 = reslist[i]
        for (j=i+1; j<=n-1; j++) {
          r2 = reslist[j]
          if (r2 - r1 > 2) break
          for (k=j+1; k<=n; k++) {
            r3 = reslist[k]
            if (r3 - r2 > 2) break

            s = rsa_map[chain, r1] + rsa_map[chain, r2] + rsa_map[chain, r3]
            if (s + 1e-12 >= THRESHOLD) {
              printf "%s%d,%s%d,%s%d\n", chain, r1, chain, r2, chain, r3
            }
          }
        }
      }
    }
  }
' "$target"
)"

if [[ -z "$patches" ]]; then
  echo "No hotspot patches found (after RSA thresholding) in: $target" >&2
  exit 0
fi

# ---- Generate one script per patch ----
n=0
while IFS= read -r patch; do
  [[ -n "$patch" ]] || continue
  ((n++)) || true

  patch_slug="$(echo "$patch" | tr ',' '_' | tr -c 'A-Za-z0-9_-' '_' | sed 's/__\+/_/g')"
  JOB_FILENAME="job__fw${fw_tag}__tg${tg_tag}__T${threshold}__hs${patch_slug}"
  script_path="${JOBS_DIR}/${JOB_FILENAME}.sh"
  log_path="${LOGDIR}/${JOB_FILENAME}.log"

custom_name_cmd=()
if [[ -n $CUSTOM_NAME ]]; then
custom_name_cmd=( --output-name "$CUSTOM_NAME")
fi

results_cmd=()
if [[ -n RESULTS_DIR ]]; then
results_cmd=( --results-dir "$RESULTS_DIR")
fi

  cat > "$script_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="\$(realpath "\${BASH_SOURCE[0]}")"
SCRIPT_DIR="\$(dirname "\$SCRIPT_PATH")"

# Walk up until we find RFantibody
ROOTDIR="\$SCRIPT_DIR"
while [[ "\$ROOTDIR" != "/" && "\$(basename "\$ROOTDIR")" != "RFantibody" ]]; do
  ROOTDIR="\$(dirname "\$ROOTDIR")"
done

if [[ "\$(basename "\$ROOTDIR")" != "RFantibody" ]]; then
  echo "Error: Could not locate RFantibody root directory."
  exit 1
fi

# Auto-generated by: scripts/util/make_patch_quiver_script.sh
# framework: $framework
# target:    $target
# patch:     $patch
# threshold: $threshold
# start:     ${start_spec:-<none>}
mkdir -p \$(dirname $log_path)
touch $log_path
nohup bash "\$ROOTDIR/scripts/pipeline_rfantibody.sh" \\
  --n-designs $N_DESIGNS --n-seqs $N_SEQS --n-recycles $N_RECYCLES --cuda-device $CUDA \\
  --design-loops $DESIGN_LOOPS \\
  -f "$framework" \\
  -t "$target" \\
  --hotspots "$patch" \\
  ${results_cmd[@]} \\
  > "$log_path" 2>&1
EOF

  chmod +x "$script_path"
done <<< "$patches"

echo "Generated ${n} scripts in: ${JOBS_DIR}"
echo "Logs will go to: ${LOGDIR}"
