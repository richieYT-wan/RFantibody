# RFantibody/workflows/rules/process_target.smk

# Allow chains_tag to be empty OR like: _chains_A_B
# TODO: THE CURRENT DEFINITION WILL MATCH ANY CHAIN TAG, AND IF APPROPRIATE WILL WORK
#       BUT THE ACTUAL CHAIN BEING PROCESSED IS DEFINED IN THE config.yaml (A only by default)
#       Potentially very bad behaviour as we could end up with files _chains_B when the config.yaml is not defined as chain B.
#       --> think of another way to handle this (maybe without changing too many things here?)
wildcard_constraints:
    chains_tag = r"(_chains_[A-Za-z0-9_]+)?"

rule download_target_pdb:
    output:
        "data/01_raw/target/{target_id}.pdb"
    params:
        url=lambda wildcards: config["targets"][wildcards.target_id]["rcsb_pdb_url"]
    shell:
        "curl -L {params.url} -o {output}"

rule clean_target_pdb:
    input:
        pdb="data/01_raw/target/{target_id}.pdb",
        script="scripts/pipeline_clean_target.sh"
    output:
        processed_pdb="data/02_intermediate/target/{target_id}_processed{chains_tag}.pdb"
    params:
        chains=lambda wildcards: config["targets"][wildcards.target_id].get("chains", ""),
        ligands=lambda wildcards: config["targets"][wildcards.target_id].get("ligands", ""),
        cutoff=lambda wildcards: config["targets"][wildcards.target_id].get("cutoff", ""),
        run_dssp=lambda wildcards: config["targets"][wildcards.target_id].get("run_dssp", True),
        threshold=lambda wildcards: config["targets"][wildcards.target_id].get("dssp_threshold", ""),
        renumber=lambda wildcards: config["targets"][wildcards.target_id].get("renumber", False)
    conda:
        "../envs/ada.yaml"
    shell:
        r"""
        CMD_ARGS=""

        if [ -n "{params.chains}" ]; then
            CMD_ARGS+=" --chains {params.chains}"
        fi
        if [ -n "{params.ligands}" ]; then
            CMD_ARGS+=" --ligands {params.ligands}"
        fi
        if [ -n "{params.cutoff}" ]; then
            CMD_ARGS+=" --cutoff {params.cutoff}"
        fi

        # Snakemake bools become 'True'/'False' strings here, so test explicitly:
        if [ "{params.run_dssp}" = "True" ]; then
            CMD_ARGS+=" --run_dssp"
            if [ -n "{params.threshold}" ]; then
                CMD_ARGS+=" --threshold {params.threshold}"
            fi
        fi

        if [ "{params.renumber}" = "True" ]; then
            CMD_ARGS+=" --renumber"
        fi

        bash {input.script} \
            -i {input.pdb} \
            -o {output.processed_pdb} \
            $CMD_ARGS
        """
