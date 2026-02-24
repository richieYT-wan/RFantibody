from utils import get_exp_cfg, get_run_cfg
#########################################
# run the RFantibody design pipeline for each patch script
#########################################

rule run_rfantibody:
    input:
        jobs_dir="data/03_jobs/{run_id}/jobs",
        manifest="data/03_jobs/{run_id}/jobs_list.tsv"
    output:
#         results_dir=directory("data/04_results/{run_id}/"),
        done=("data/04_results/{run_id}/rfab_run.complete")
#     params:
#         n_jobs=
    shell:
        """
        set -euxo pipefail
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

        while IFS= read -r job; do
        [ -n "$job" ] || continue
        bash "{input.jobs_dir}/$job"
        done < "{input.manifest}"

        touch "{output.done}"
        """
