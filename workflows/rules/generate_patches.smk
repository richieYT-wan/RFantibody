#########################################
# generate hotspot patches (patch scripts)
#########################################

rule generate_patches:
    input:
        framework = "data/02_intermediate/framework/{framework_id}_HLT.pdb",
        target    = "data/02_intermediate/target/{target_id}_processed_chains_{chains}.pdb"
    output:
        patches_dir = directory("data/03_outputs/{run_id}/patch_scripts")
    params:
        experiment = lambda wildcards: config["runs"][wildcards.run_id]["experiment"],
        # RSA threshold is controlled by the experiment; if no `rsa_threshold` field exists,
        # fall back to hotspot_prop to remain compatible with your original config
        # TBD: read from config; rsa_threshold = lambda wildcards: config["experiments"][config["runs"][wildcards.run_id]["experiment"]].get("rsa_threshold", 1.5),
        # TBD: read from config; design_loops = lambda wildcards: config["experiments"][config["runs"][wildcards.run_id]["experiment"]]["design_loops"],
        # TBD: read from config; n_designs = lambda wildcards: config["experiments"][config["runs"][wildcards.run_id]["experiment"]]["n_designs"],
        # TBD: read from config; n_seqs = lambda wildcards: config["experiments"][config["runs"][wildcards.run_id]["experiment"]]["n_seqs"],
        # TBD: read from config; n_recycles = lambda wildcards: config["experiments"][config["runs"][wildcards.run_id]["experiment"]]["n_recycles"],
        # TBD: read from config; cuda_device = "0",
        # TBD: read from config; start_spec = lambda wildcards: config["targets"][wildcards.target_id].get("start_spec", "")
    shell:
        """
        mkdir -p {{output.patches_dir}}
        # run your patch‑generation script with the correct RSA threshold (-T)
        # and starting residue (-S) if provided.  This script writes patch scripts into scripts/rfantibody_jobs/
        bash scripts/util/make_patch_pipeline_script.sh \
            -f {{input.framework}} \
            -t {{input.target}} \
            -T {{params.rsa_threshold}} \
            -c {{params.cuda_device}} \
            -d {{params.n_designs}} \
            -s {{params.n_seqs}} \
            -r {{params.n_recycles}} \
            -L "{{params.design_loops}}" \
            {{ '--S ' + params.start_spec if params.start_spec else '' }}
        # copy the generated patch scripts and logs into your output directory
        cp -r scripts/rfantibody_jobs/* {{output.patches_dir}}/
        """
