from utils import get_exp_cfg, get_run_cfg
#########################################
# run the RFantibody design pipeline for each patch script
#########################################

rule run_rfantibody:
    input:
        logs_dir=directory("data/03_jobs/{run_id}/jobs/logs"),
        jobs_dir=directory("data/03_jobs/{run_id}/jobs"),
        manifest="data/03_jobs/{run_id}/jobs_list.tsv"
    output:
        results_dir=directory("data/04_results/{run_id}/*"),
#         logs="data/03_jobs/{run_id}/jobs/logs/*.log",
        done=("data/04_results/{run_id}/rfab_run.complete")
#     params:
#         n_jobs=
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname "{output.done}")"
        # TODO: This needs to change from sequential to parallel runs to save a lot of time
        # Currently, each job is ran sequentially for this pipe to run
        # which is not the wanted behaviour for gbatch
        # Need to make new ruleset for parallel running like on VertexAI with multiple_concurrent_jobs.sh
        if [[ -f {input.manifest} ]]; then
        echo "#####################################################"
        echo {input.manifest}
        echo "#####################################################"
        fi
        
        JOBS_DIR={input.jobs_dir}
        while IFS= read -r job; do
        [ -n "$job" ] || continue
            log="$JOBS_DIR/logs/${{job%.sh}}.log"
            mkdir -p "$(dirname "${{log}}")"

            echo "=== RUNNING: ${{job}} ==="
            bash "$JOBS_DIR/$job" >"$log" 2>&1 || {{
                echo "=== FAILED: ${{job}} ===" >&2
                echo "=== LAST 100 LINES OF LOG: ${{log}} ===" >&2
                tail -n 100 "$log" >&2 || true
                exit 1
            }}
        done < "{input.manifest}"
        """
