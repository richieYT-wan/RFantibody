# workflows/rules/process_target.smk

rule download_target:
    output:
        #TBD, to be saved at pdb="data/01_raw/target/{target_id}.pdb"
    params:
        #TBD, to parse from config url=lambda wc: config["targets"][wc.target_id]["rcsb_pdb_url"]
    shell:
        r"""
        mkdir -p $(dirname {output.pdb})
        curl -L "{params.url}" -o "{output.pdb}"
        """

rule process_target:
    input:
        #TBD: at raw="data/01_raw/target/{target_id}.pdb"
    output:
        #TBD: at processed_chains="data/02_intermediate/target/{target_id}_processed_chains_{chains}.pdb"
    params:
        #TBD: to parse from config; chains=lambda wc: config["targets"][wc.target_id]["chains"],
        #TBD: to parse from config; ligands=lambda wc: config["targets"][wc.target_id].get("ligands", ""),
        #TBD: to parse from config; cutoff=lambda wc: config["targets"][wc.target_id].get("cutoff", 4.0),
        #TBD: to parse from config; run_dssp=lambda wc: config["targets"][wc.target_id].get("run_dssp", False),
        #TBD: to parse from config; thr=lambda wc: config["targets"][wc.target_id].get("dssp_threshold", 0.4),
        #TBD: to parse from config; renumber=lambda wc: config["targets"][wc.target_id].get("renumber", False),
    shell:
        r"""
#         mkdir -p data/02_intermediate/target

#         outprefix="data/02_intermediate/target/{wildcards.target_id}"
#         extra=()
#         [[ -n "{params.ligands}" ]] && extra+=( --ligands "{params.ligands}" )
#         [[ "{params.renumber}" == "True" ]] && extra+=( --renumber )
#         if [[ "{params.run_dssp}" == "True" ]]; then
#           extra+=( --run_dssp --threshold "{params.thr}" )
#         fi

#         bash scripts/pipeline_clean_target.sh \
#           -i "{input.raw}" \
#           -o "$outprefix" \
#           --chains "{params.chains}" \
#           --cutoff "{params.cutoff}" \
#           "${extra[@]}"

#         # Your script likely writes *_processed*.pdb; copy to deterministic outputs:
#         cp -f "${outprefix}_processed_chains_{params.chains}.pdb" "{output.processed_chains}"
        """
