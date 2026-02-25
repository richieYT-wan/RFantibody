
#!/bin/bash
set -euo pipefail

# This script exists as an alternative to make_patch_pipeline_script.sh due to Snakemake limitations I ran into for passing ALL the inputs/outputs directly.
# This will call the legacy script, generate those same arguments (related to hotspot picking), then explicitly omit inputs/outputs 
# so that the rest of the pipeline can handle input targets/frameworks and output directories (Snakemake gbucket integration limitation)
# This is done because Snakemake when integrating buckets need to stage I/O and needs explicit input and output fields.
#
# make_patch_args.sh
#
# Wraps legacy make_patch_pipeline_script.sh:
# - generates job__*.sh in a temp dir
# - extracts pipeline_rfantibody.sh CLI args
# - strips -f/-t/--results-dir (and their values)
# - writes job__*.args (one token per line) into OUTDIR

usage() {
  cat >&2 <<'EOF'
Usage:
  make_patch_args.sh [OPTIONS]

Required arguments:
  -f, --framework PATH        Path to framework PDB (HLT)
  -t, --target PATH           Path to target PDB (processed)
  -T, --threshold FLOAT       Summed RSA threshold value
  -O, --jobs-dir DIR          Output jobs directory (writes *.args + logs/)
  -R, --results-dir DIR       Results directory (passed to legacy generator for naming; stripped from args)

Optional arguments (passed through to legacy generator):
  -S, --start-spec STR
  -c, --cuda INT
  -d, --n-designs INT
  -s, --n-seqs INT
  -r, --n-recycles INT
  -L, --design-loops STR
  -F, --format STR
  --diffuser-t INT
EOF
  exit 2
}

framework=""
target=""
threshold=""
start_spec=""
CUDA=""
N_DESIGNS=""
N_SEQS=""
N_RECYCLES=""
DESIGN_LOOPS=""
DIFFUSER_T=""
FORMAT=""
JOBS_DIR=""
RESULTS_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--framework) framework="$2"; shift 2 ;;
    -t|--target) target="$2"; shift 2 ;;
    -T|--threshold) threshold="$2"; shift 2 ;;
    -S|--start-spec) start_spec="$2"; shift 2 ;;
    -c|--cuda) CUDA="$2"; shift 2 ;;
    -d|--n-designs) N_DESIGNS="$2"; shift 2 ;;
    -s|--n-seqs) N_SEQS="$2"; shift 2 ;;
    -r|--n-recycles) N_RECYCLES="$2"; shift 2 ;;
    -L|--design-loops) DESIGN_LOOPS="$2"; shift 2 ;;
    -F|--format) FORMAT="$2"; shift 2 ;;
    --diffuser-t) DIFFUSER_T="$2"; shift 2 ;;
    -O|--jobs-dir) JOBS_DIR="$2"; shift 2 ;;
    -R|--results-dir) RESULTS_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -n "$framework" && -n "$target" && -n "$threshold" && -n "$JOBS_DIR" && -n "$RESULTS_DIR" ]] || usage

mkdir -p "$JOBS_DIR" "$JOBS_DIR/logs"

# locate RFantibody root (same style as legacy)
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$SCRIPT_DIR"
while [[ "$ROOT_DIR" != "/" && "$(basename "$ROOT_DIR")" != "RFantibody" ]]; do
  ROOT_DIR="$(dirname "$ROOT_DIR")"
done
if [[ "$(basename "$ROOT_DIR")" != "RFantibody" ]]; then
  echo "ERROR: Could not locate RFantibody root directory." >&2
  exit 2
fi

LEGACY="$ROOT_DIR/scripts/util/make_patch_pipeline_script.sh"
[[ -f "$LEGACY" ]] || { echo "ERROR: legacy script not found: $LEGACY" >&2; exit 2; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# run legacy generator into tempdir (produces job__*.sh)
LEGACY_ARGS=( -f "$framework" -t "$target" -T "$threshold" -O "$tmpdir" -R "$RESULTS_DIR" )
[[ -n "$start_spec" ]] && LEGACY_ARGS+=( -S "$start_spec" )
[[ -n "$CUDA" ]] && LEGACY_ARGS+=( -c "$CUDA" )
[[ -n "$N_DESIGNS" ]] && LEGACY_ARGS+=( -d "$N_DESIGNS" )
[[ -n "$N_SEQS" ]] && LEGACY_ARGS+=( -s "$N_SEQS" )
[[ -n "$N_RECYCLES" ]] && LEGACY_ARGS+=( -r "$N_RECYCLES" )
[[ -n "$DESIGN_LOOPS" ]] && LEGACY_ARGS+=( -L "$DESIGN_LOOPS" )
[[ -n "$FORMAT" ]] && LEGACY_ARGS+=( -F "$FORMAT" )
[[ -n "$DIFFUSER_T" ]] && LEGACY_ARGS+=( --diffuser-t "$DIFFUSER_T" )

bash "$LEGACY" "${LEGACY_ARGS[@]}"

shopt -s nullglob
scripts=( "$tmpdir"/*.sh )
if [[ ${#scripts[@]} -eq 0 ]]; then
  echo "ERROR: legacy generator produced no scripts in $tmpdir" >&2
  ls -lah "$tmpdir" >&2 || true
  exit 2
fi

# Extract args from each script
for script in "${scripts[@]}"; do
  bn="$(basename "$script")"
  out="$JOBS_DIR/${bn%.sh}.args"

  # capture the pipeline invocation line(s)
  # The legacy script writes: bash "$ROOTDIR/scripts/pipeline_rfantibody.sh" \
  #   --n-designs ... \
  # We'll pull all lines from that "bash ...pipeline_rfantibody.sh" until the redirection/log.
  python3 - "$script" "$out" <<'PY'
import pathlib, re, shlex, sys

script = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

text = script.read_text(encoding="utf-8", errors="replace").splitlines()

# Find the line that starts the pipeline call
start = None
for i, line in enumerate(text):
    if re.search(r'\bbash\b.*pipeline_rfantibody\.sh', line):
        start = i
        break
if start is None:
    raise SystemExit(f"Could not find pipeline_rfantibody.sh call in {script}")

# Concatenate continuation lines ending with '\'
buf = []
for j in range(start, len(text)):
    line = text[j].rstrip()
    buf.append(line)
    if not line.endswith("\\"):
        break

cmd = " ".join(l.rstrip("\\").strip() for l in buf)

# Remove output redirection if present
cmd = re.split(r'\s>\s', cmd, maxsplit=1)[0].strip()

tokens = shlex.split(cmd)

# Locate the pipeline script token
idx = None
for i, t in enumerate(tokens):
    if t.endswith("pipeline_rfantibody.sh") or t.endswith("/pipeline_rfantibody.sh"):
        idx = i
        break
if idx is None:
    raise SystemExit(f"Could not locate pipeline_rfantibody.sh token in: {cmd}")

args = tokens[idx+1:]

# Strip -f/-t/--results-dir and their values
skip_flags = {"-f", "--framework", "-t", "--target", "--results-dir"}
filtered = []
skip_next = False
for a in args:
    if skip_next:
        skip_next = False
        continue
    if a in skip_flags:
        skip_next = True
        continue
    if any(a.startswith(f + "=") for f in skip_flags):
        continue
    filtered.append(a)

# Write one token per line
out.write_text("\n".join(filtered) + "\n", encoding="utf-8")
PY
done

echo "Generated ${#scripts[@]} args files in: ${JOBS_DIR}"