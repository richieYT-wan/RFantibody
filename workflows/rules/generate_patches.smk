#########################################
# generate hotspot patches (patch scripts)
#########################################

import os
from pathlib import Path

def _get_run_cfg(run_id):
    return config["runs"][run_id]

def _get_exp_cfg(run_id):
    # use wildcard to get run_id --> read the config's experiment based on the experiment noted in a run's parameters
    experiment = _get_run_cfg(run_id)["experiment"]
    return config["experiments"][experiment]

def target_processed_path(target_id):
    # must match your process_target.smk naming convention
    chains = config["targets"][target_id].get("chains")
    if chains:
        return f"data/02_intermediate/target/{target_id}_processed_chains_{chains.replace(',', '_')}.pdb"
    return f"data/02_intermediate/target/{target_id}_processed.pdb"

rule generate_patches:
    input:
        framework=lambda wildcards: f"data/02_intermediate/framework/{_get_run_cfg(wildcards.run_id)['framework_id']}_HLT.pdb",
        target=lambda wildcards: target_processed_path(_get_run_cfg(wildcards.run_id)["target_id"]),
        generator="scripts/util/make_patch_pipeline_script.sh"
    output:
        patches_dir=directory("data/03_outputs/{run_id}/patch_scripts_qv"),
        manifest="data/03_outputs/{run_id}/patch_scripts_qv/jobs.tsv"
    params:
        # experiment-level params
        # Here, get _get_exp_cfg reads experiment configs and give experiment-related params (like threshold etc)
        # use the wildcards.run_id because the run_id defines experiment in their field
        rsa_threshold=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("rsa_threshold", "")),
        design_loops=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("design_loops", "")),
        start_spec=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("start_spec", "")),
        n_designs=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("n_designs", 10)),
        n_seqs=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("n_seqs", 10)),
        n_recycles=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("n_recycles", 10)),
        cuda_device=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("cuda_device", 0)),
        format=lambda wildcards: str(_get_exp_cfg(wildcards.run_id).get("format", "qv"))
    shell:
        r"""
        set -euo pipefail

        mkdir -p "{output.patches_dir}"
        cd "{output.patches_dir}"

        FW="$(realpath "{input.framework}")"
        TG="$(realpath "{input.target}")"

        # Run generator inside run-specific folder so it doesn't collide with other runs
        bash "$(realpath "{input.generator}")" \
          -f "$FW" \
          -t "$TG" \
          -T "{params.rsa_threshold}" \
          -c "{params.cuda_device}" \
          -d "{params.n_designs}" \
          -s "{params.n_seqs}" \
          -r "{params.n_recycles}" \
          {{"-L \"{params.design_loops}\"" if params.design_loops else ""}} \
          {{"-S \"{params.start_spec}\"" if params.start_spec else ""}}

        # Generator writes into ./scripts/rfantibody_jobs/
        if [ ! -d "./scripts/rfantibody_jobs" ]; then
          echo "ERROR: generator did not create ./scripts/rfantibody_jobs" >&2
          exit 2
        fi

        # Move scripts to patches_dir root
        find "./scripts/rfantibody_jobs" -maxdepth 1 -type f -name "*.sh" -print0 \
          | xargs -0 -I{} mv -f {} .

        # Optional: keep logs dir where it is, but remove empty scripts dir
        # (generator also creates ./scripts/rfantibody_jobs/logs)
        if [ -d "./scripts/rfantibody_jobs/logs" ]; then
          mkdir -p "./logs"
          # keep logs local to patch_scripts for convenience
          mv -f ./scripts/rfantibody_jobs/logs/* ./logs/ 2>/dev/null || true
        fi
        rm -rf "./scripts"

        # Write manifest
        : > "{output.manifest}"
        for s in *.sh; do
          [ -e "$s" ] || break
          printf "%s\t%s\n" "$s" "$(realpath "$s")" >> "{output.manifest}"
        done

        # Sanity
        if [ ! -s "{output.manifest}" ]; then
          echo "ERROR: no patch scripts generated (manifest empty): {output.manifest}" >&2
          exit 2
        fi
        """
