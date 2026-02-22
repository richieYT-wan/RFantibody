from utils import get_run_cfg, get_exp_cfg
#########################################
# parse RFantibody outputs into a CSV
#########################################

rule parse_outputs:
    input:
        complete="data/04_results/{run_id}/.complete",
        input_dir="data/04_results/{run_id}/"
    output:
        complete="data/04_results/{run_id}/.parse_complete",
    params:
        format = lambda wildcards: str(get_exp_cfg(wildcards.run_id, config).get("format", "qv"))
    shell:
        """
        set -euxo pipefail
        # list all the results directories within the run
        indir=$(dirname {input.complete})
        
        if [[ "{params.format}" == "qv" ]]; then
            RESULTS_PATH="03_RF2_folds.qv"
        elif [[ "{params.format}" == "pdb" ]]; then
            RESULTS_PATH="03_RF2_folds/"
        fi
        for f in $(ls ${{indir}} | grep -v .complete); do 
            echo ${{f}}
            bash scripts/parse_output.sh --format {params.format} -i "data/04_results/{wildcards.run_id}/${{f}}/${{RESULTS_PATH}}" -o "parsed_outputs_smk.csv"
        done
        touch {output}
        """

rule merge_outputs:
    input:
        complete="data/04_results/{run_id}/.parse_complete",
        run_dir="data/04_results/{run_id}/"
    output:
        csv="data/04_results/{run_id}/merged_parsed_outputs.csv"
    conda:
        "../envs/ada.yaml"
    run:
        import os
        import glob
        import pandas as pd
        # glob all the ./parsed_output.csv files
        print(f"{input.run_dir}/*/*smk*.csv")
        files = glob.glob(f"{input.run_dir}/*/*parsed_outputs_smk.csv*")
        # read + concat 
        df = pd.concat([pd.read_csv(x) for x in files])
        # save to merged results
        df.to_csv(f"{output.csv}", index=False)
        

