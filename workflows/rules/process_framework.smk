# RFantibody/workflows/rules/process_framework.smk

rule download_framework_pdb:
    output:
        "data/01_raw/framework/{framework_id}_chothia.pdb"
    params:
        url=lambda wildcards: config["frameworks"][wildcards.framework_id]["sabdab_chothia_url"]
    shell:
        "curl -L {params.url} -o {output}"

rule process_framework_to_hlt:
    input:
        pdb="data/01_raw/framework/{framework_id}_chothia.pdb"
    output:
        hlt="data/02_intermediate/framework/{framework_id}_HLT.pdb"
    params:
        chain=lambda wildcards: config["frameworks"][wildcards.framework_id]["chain"],
        kind=lambda wildcards: config["frameworks"][wildcards.framework_id]["kind"],
        # The script path is relative to the RFantibody/ root, which is our workdir
        script_base_dir="scripts",
        # The conversion script expects the output basename without the .pdb extension
        output_basename=lambda wildcards: wildcards.framework_id + "_HLT"
    shell:
        """
        if [ "{params.kind}" = "nanobody" ]; then
            CONVERSION_SCRIPT="{params.script_base_dir}/convert_chothia2hlt_nanobody.sh"
        elif [ "{params.kind}" = "antibody" ]; then
            CONVERSION_SCRIPT="{params.script_base_dir}/convert_chothia2hlt_antibody.sh"
        else
            echo "Error: Unknown framework kind '{params.kind}' for {wildcards.framework_id}" >&2
            exit 1
        fi
        

        # The script assumes it's run from the RFantibody/ root, which Snakemake's workdir handles.
        # It also handles creating the 'processed' directory and adding the .pdb extension.
        bash "$CONVERSION_SCRIPT" \
            -f "{input.pdb}" \
            -h "{params.chain}" \
            -o "{output.hlt}"
        """
