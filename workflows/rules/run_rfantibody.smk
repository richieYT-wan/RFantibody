#########################################
# run the RFantibody design pipeline for each patch script
#########################################

rule run_rfantibody:
    input:
        # TBD: read scripts from patches_dir = "data/03_outputs/{run_id}/patch_scripts"
    output:
        done = touch("data/03_outputs/{run_id}/rfantibody_complete.txt")
    params:
        # results and logs directories can come from config if desired
        # TBD: to define ? cuda_device = "0"
    shell:
        """
        mkdir -p $(dirname {{output.done}})
        # each patch script already calls pipeline_rfantibody.sh; run them sequentially
        for patch_script in {{input.patches_dir}}/run_*; do
            bash "$patch_script"
        done
        # mark as done
        touch {{output.done}}
        """
