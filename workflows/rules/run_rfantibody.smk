#########################################
# run the RFantibody design pipeline for each patch script
#########################################
from utils import get_run_cfg

rule run_rfantibody:
    input:
        *setup_inputs(),
        framework=lambda wc: f"data/02_intermediate/framework/{get_run_cfg(wc.run_id, config)['framework_id']}_HLT.pdb",
        target=lambda wc: f"data/02_intermediate/target/{get_run_cfg(wc.run_id, config)['target_id']}_processed.pdb",
        script=local("scripts/pipeline_rfantibody.sh"),
        jobs_dir="data/03_jobs/{run_id}/jobs",
        manifest="data/03_jobs/{run_id}/jobs_list.tsv",
    output:
        results_dir=directory("data/04_rfab/{run_id}"),
        done="data/04_rfab/{run_id}/rfab_run.complete",
    resources:
        googlebatch_job_name=lambda wc: f"rfab-{wc.run_id}-run_rfab",
        googlebatch_labels="workflow=rfantibody,step=rf2",
        accelerator_type="nvidia-tesla-v100",
        accelerator_count=1
    shell:
        r"""
        set -euo pipefail
        JOBS_DIR="{input.jobs_dir}"
        RESULTS_DIR="{output.results_dir}"
        mkdir -p "$RESULTS_DIR" "$JOBS_DIR/logs"
        mkdir -p "$(dirname "{output.done}")"

        RFAB_SCRIPT="{input.script}"
        FW="{input.framework}"
        TG="{input.target}"

        while IFS= read -r arg_bn; do
        arg_bn="${{arg_bn%$'\r'}}"
        [[ -n "$arg_bn" ]] || continue

        args_path="$JOBS_DIR/$arg_bn"
        [[ -f "$args_path" ]] || {{ echo "ERROR: missing args file: $args_path" >&2; exit 2; }}

        log="$JOBS_DIR/logs/${{arg_bn%.args}}.log"
        mkdir -p "$(dirname "$log")"

        mapfile -t ARGS < "$args_path"
        CLEAN_ARGS=()
        for a in "${{ARGS[@]}}"; do
            a="${{a%$'\r'}}"
            [[ -n "$a" ]] || continue
            CLEAN_ARGS+=("$a")
        done

        echo "=== RUNNING: $arg_bn ==="
        bash "$RFAB_SCRIPT" -f "$FW" -t "$TG" --results-dir "$RESULTS_DIR" "${{CLEAN_ARGS[@]}}" >"$log" 2>&1 || {{
            echo "=== FAILED: $arg_bn ===" >&2
            echo "=== LAST 100 LINES OF LOG: $log ===" >&2
            tail -n 100 "$log" >&2 || true
            exit 1
        }}
        done < "{input.manifest}"

        touch "{output.done}"
        """