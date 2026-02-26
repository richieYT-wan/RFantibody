# This rule exists only for google batch, to manually run the uv setup
rule gbatch_install_uv:
    output:
        "data/00_setup/.uv_setup.complete"
    resources:
        googlebatch_job_name="rfab-uvsetup",
        accelerator_type="nvidia-tesla-v100", # Needs a GPU to run the setup
        accelerator_count=1,
    shell:
        r"""
		# debug part to remove
		set -euxo pipefail
		echo "$(pwd)"
		echo "$(ls -R | head)"
		# debug part to remove

        bash setup.sh
        mkdir -p $(dirname {output})
        touch {output}
        """
