from utils import get_run_cfg, get_exp_cfg
#########################################
# parse RFantibody outputs into a CSV
#########################################

rule parse_outputs:
    input:
        complete="data/04_rfab/{run_id}/rfab_run.complete",
        script=local("scripts/parse_output.sh")
    output:
        complete="data/05_results/{run_id}/parse.log",
    params:
        format = lambda wildcards: str(get_exp_cfg(wildcards.run_id, config).get("format", "qv")),
        run_dir = lambda wildcards: f"data/05_results/{wildcards.run_id}"
    resources:
        googlebatch_job_name=lambda wc: f"rfab-{wc.run_id}-parse_output_1",
        accelerator_type="nvidia-tesla-v100",
        accelerator_count=1,
    conda:
        str(ADAENV)
    shell:
        """
        set -euo pipefail
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
            # ${{f}} here is each subfolder (as created by run_rfantibody), $RESULTS_PATH the path to 03_RF2_folds results
            # If doesn't exist, means the RFab run did not complete (for whatever reason)
            # --> Then, do not run parse_output and instead write to a logfile that ${{f}} is missing
            # Write the logs in parse.log
            FULLPATH="${{indir}}/${{f}}/${{RESULTS_PATH}}"
            if [[ -f $FULLPATH || -d $FULLPATH ]]; then
                echo "Parsing outputs from ${{FULLPATH}}" >> ${{tmplog}}
                bash {input.script} --format {params.format} -i ${{FULLPATH}} -o "parsed_outputs_smk.csv"
            else
                echo "Parsing incomplete; ${{FULLPATH}} not found." >> ${{tmplog}}
            fi

        done
        mv ${{tmplog}} {output}
        """

rule merge_outputs:
    input:
        complete="data/05_results/{run_id}/parse.log",
        run_dir="data/04_rfab/{run_id}"
    output:
        csv="data/05_results/{run_id}/merged_parsed_outputs.csv"
    params:
        run_dir=lambda wildcards: f"data/04_results/{wildcards.run_id}"
    conda:
        str(ADAENV)
    resources:
        googlebatch_job_name=lambda wc: f"rfab-{wc.run_id}-parse_output_1"
    run:
        import os
        import glob
        import pandas as pd
        # glob all the ./parsed_output.csv files
        files = glob.glob(f"{input.run_dir}/*/*parsed_outputs_smk.csv*")
        # read + concat 
        df = pd.concat([pd.read_csv(x) for x in files])
        # save to merged results
        df.to_csv(f"{output.csv}", index=False)
        

