# RFantibody/workflows/rules/process_target.smk

# Allow chains_tag to be empty OR like: _chains_A_B
# TODO: THE CURRENT DEFINITION WILL MATCH ANY CHAIN TAG, AND IF APPROPRIATE WILL WORK
#       BUT THE ACTUAL CHAIN BEING PROCESSED IS DEFINED IN THE config.yaml (A only by default)
#       Potentially very bad behaviour as we could end up with files _chains_B when the config.yaml is not defined as chain B.
#       --> think of another way to handle this (maybe without changing too many things here?)
wildcard_constraints:
    chains_tag = r"(_chains_[A-Za-z0-9_]+)?"

# Convoluted workaround due to naming conventions and Snakemake DAG limitations...
rule download_target_pdb:
    output:
        # TODO CHECKS: cant we just have {savefile} as the wildcard here and define it in the snake?
        "data/01_raw/target/{target_id}.pdb"
    params:
        url=lambda wildcards: config["targets"][wildcards.target_id]["rcsb_pdb_url"],
        save_filename= lambda wildcards: config['targets'][wildcards.target_id]['save_filename']
    shell:
        """
        # like here it would be -o {params.save_filename} and we touch {output} then delete in the next part ?
        # ^THAT^ OR we just leave it as it is OR we accept duplicates target files with just _A/B/etc. filenames
        curl -L {params.url} -o {output}
        """

rule clean_target_pdb:
    input:
        pdb="data/01_raw/target/{target_id}.pdb",
        script=local("scripts/pipeline_clean_target.sh")
    output:
        processed_pdb="data/02_intermediate/target/{target_id}_processed.pdb",
        dssp="data/01_raw/target/{target_id}_dssp.csv"
    params:
        save_filename=lambda wildcards: config["targets"][wildcards.target_id]['save_filename'],
        chains=lambda wildcards: config["targets"][wildcards.target_id].get("chains", ""),
        ligands=lambda wildcards: config["targets"][wildcards.target_id].get("ligands", ""),
        cutoff=lambda wildcards: config["targets"][wildcards.target_id].get("cutoff", ""),
        run_dssp=lambda wildcards: config["targets"][wildcards.target_id].get("run_dssp", True),
        threshold=lambda wildcards: config["targets"][wildcards.target_id].get("dssp_threshold", ""),
        renumber=lambda wildcards: config["targets"][wildcards.target_id].get("renumber", False)
    conda:
        str(ADAENV)
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname "{output.processed_pdb}")"

        CMD_ARGS=()

        if [[ -n "{params.chains}" ]]; then
            CMD_ARGS+=(--chains "{params.chains}")
        fi
        if [[ -n "{params.ligands}" ]]; then
            CMD_ARGS+=(--ligands "{params.ligands}")
        fi
        if [[ -n "{params.cutoff}" ]]; then
            CMD_ARGS+=(--cutoff "{params.cutoff}")
        fi

        if [[ "{params.run_dssp}" == "True" ]]; then
            CMD_ARGS+=(--run_dssp)
            if [[ -n "{params.threshold}" ]]; then
                CMD_ARGS+=(--threshold "{params.threshold}")
            fi
        fi

        if [[ "{params.renumber}" == "True" ]]; then
            CMD_ARGS+=(--renumber)
        fi

        bash "{input.script}" -i "{input.pdb}" -o "{output.processed_pdb}" "${{CMD_ARGS[@]}}"
        mv "{input.pdb}" "$(dirname {input.pdb})/{params.save_filename}"
        """