#########################################
# download and convert frameworks to HLT
#########################################

# download raw framework in Chothia format
rule download_framework:
    output:
        #TBD: should be "data/01_raw/framework/{framework_id}_chothia.pdb"
    params:
        url = #TBD
    shell:
        """
        mkdir -p $(dirname {output})
        curl -L {{params.url}} -o {{output}}
        """

# convert chothia PDB to HLT using the appropriate script
rule convert_framework:
    input:
        raw = "data/01_raw/framework/{framework_id}_chothia.pdb"
    output:
        hlt = "data/02_intermediate/framework/{framework_id}_HLT.pdb"
    params:
        # TBD, to parse from config kind = lambda wildcards: config["frameworks"][wildcards.framework_id]["kind"],
        # TBD, to parse from config chain = lambda wildcards: config["frameworks"][wildcards.framework_id]["chain"]
    shell:
        """
        mkdir -p $(dirname {{output.hlt}})
        # choose the correct conversion script based on kind
        if [[ "{{params.kind}}" == "antibody" ]]; then
            converter="scripts/convert_chothia2hlt_antibody.sh"
        else
            converter="scripts/convert_chothia2hlt_nanobody.sh"
        fi
        # convert using the chain specified in the config
        bash $converter -f {{input.raw}} -h {{params.chain}}
        # your scripts save to inputs/framework/processed/
        # copy it into data/02_intermediate/framework with a deterministic name
        cp inputs/framework/processed/*_HLT.pdb {{output.hlt}}
        """
