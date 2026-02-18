import os
from workflows.utils import (
    sanitize,
    get_framework_ids, get_target_ids, get_run_ids, get_patch_run_ids,
    run_cfg, patch_run_cfg,
    fw_raw_path, fw_hlt_path,
    tg_raw_path, tg_processed_path,
)

RESULTS_DIR = config.get("results_dir", "results")  # kept for compatibility; not used
LOGS_DIR = config.get("logs_dir", "logs")

# “all” target: build parsed outputs for runs and patch runs
rule all:
    input:
        # single runs parsed table
        expand("data/03_outputs/parsed/{run_id}.csv", run_id=get_run_ids(config))
        +
        # patch runs completion marker
        expand("data/03_outputs/patch_runs/{patch_run_id}/all_patches.done",
               patch_run_id=get_patch_run_ids(config))
