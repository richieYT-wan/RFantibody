#########################################
# parse RFantibody outputs into a CSV
#########################################

rule parse_outputs:
    input:
        complete = "data/03_outputs/{run_id}/rfantibody_complete.txt"
    output:
        "results/{run_id}/parsed_outputs.csv"
    params:
        fmt = lambda wildcards: config["experiments"][config["runs"][wildcards.run_id]["experiment"]]["format"]
    shell:
        """
        mkdir -p $(dirname {{output}})
        # find the first .qv or .pdb file under the output directory
        result_file=$(find data/03_outputs/{{wildcards.run_id}} -type f \\( -name '*.qv' -o -name '*.pdb' \\) | head -n 1)
        # call parse_output.sh with the appropriate format
        bash scripts/parse_output.sh --format {{params.fmt}} -i "$result_file" -o {{output}}
        """
