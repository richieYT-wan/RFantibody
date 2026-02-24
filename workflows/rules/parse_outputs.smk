from utils import get_run_cfg, get_exp_cfg
#########################################
# parse RFantibody outputs into a CSV
#########################################

rule parse_outputs:
    input:
        complete="data/04_results/{run_id}/rfab_run.complete",
#         input_dir=directory("data/04_results/{run_id}/")
    output:
        complete="data/04_results/{run_id}/parse.log",
    params:
        format = lambda wildcards: str(get_exp_cfg(wildcards.run_id, config).get("format", "qv")),
        run_dir = lambda wildcards: f"data/04_results/{wildcards.run_id}"
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
        
        tmplog=$(mktemp)
        for f in $(ls ${{indir}} | grep -v .complete); do 
            # HERE do a ls to find 03_RF2_folds. 
            # If doesn't exist, means the RFab run did not complete (for whatever reason)
            # --> Then, do not run parse_output and instead write to a logfile that ${{f}} is missing
            # Write the logs in parse.log
            FULLPATH="data/04_results/{wildcards.run_id}/${{f}}/${{RESULTS_PATH}}"
            if [[ -f $FULLPATH || -d $FULLPATH ]]; then
                echo "Parsing outputs from ${{FULLPATH}}" >> ${{tmplog}}
                bash scripts/parse_output.sh --format {params.format} -i ${{FULLPATH}} -o "parsed_outputs_smk.csv"
            else
                echo "Parsing incomplete; ${{FULLPATH}} not found." >> ${{tmplog}}
            fi

        done
        mv ${{tmplog}} {output}
        """

rule merge_outputs:
    input:
        complete="data/04_results/{run_id}/parse.log",
#         run_dir=directory("data/04_results/{run_id}/")
    output:
        csv="data/04_results/{run_id}/merged_parsed_outputs.csv"
    params:
        run_dir=lambda wildcards: f"data/04_results/{wildcards.run_id}"
    conda:
        str(ADAENV)
    run:
        import os
        import glob
        import pandas as pd
        # glob all the ./parsed_output.csv files
        files = glob.glob(f"{params.run_dir}/*/*parsed_outputs_smk.csv*")
        # read + concat 
        df = pd.concat([pd.read_csv(x) for x in files])
        # save to merged results
        df.to_csv(f"{output.csv}", index=False)
        

