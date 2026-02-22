from utils import get_exp_cfg, get_run_cfg
#########################################
# run the RFantibody design pipeline for each patch script
#########################################

rule run_rfantibody:
    input:
        jobs_dir="data/03_jobs/{run_id}/jobs",
        manifest="data/03_jobs/{run_id}/jobs_list.tsv"
    output:
        results_dir=directory("data/04_results/{run_id}/"),
        done=("data/04_results/{run_id}/.complete")
#     params:
#         n_jobs=
    shell:
        """
        set -euxo pipefail
        mkdir -p $(dirname {output.done})
        # each patch script already calls pipeline_rfantibody.sh; run them sequentially
        for job in $(cat {input.manifest}); do
            echo $job
            bash "$job"
        done
        # mark as done
        touch {output.done}
        """
