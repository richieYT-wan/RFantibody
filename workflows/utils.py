from pathlib import Path
import os
import re

def sanitize(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
    s = re.sub(r"^_+|_+$", "", s)
    s = re.sub(r"_+", "_", s)
    return s

def find_repo_root(start: Path | None = None) -> Path:
    if start is None:
        start = Path(__file__).resolve()

    current = start if start.is_dir() else start.parent

    for parent in [current] + list(current.parents):
        if (parent / "workflows").exists() and (parent / "scripts").exists():
            return parent

    raise RuntimeError("Could not find RFantibody root directory.")

def get_target_id(run_id, config):
    return config["runs"][run_id]["target_id"]
    
def get_run_cfg(run_id, config):
    return config["runs"][run_id]

def get_exp_cfg(run_id, config):
    # use wildcard to get run_id --> read the config's experiment based on the experiment noted in a run's parameters
    experiment = get_run_cfg(run_id, config)["experiment"]
    return config["experiments"][experiment]

def target_processed_path(target_id, config):
    # must match process_target.smk naming convention
    return f"data/02_intermediate/target/{target_id}_processed.pdb"

def get_framework_ids(config):
    return sorted(config.get("frameworks", {}).keys())

def get_target_ids(config):
    return sorted(config.get("targets", {}).keys())

def get_run_ids(config):
    return sorted(config.get("runs", {}).keys())

def get_patch_run_ids(config):
    return sorted(config.get("patch_runs", {}).keys())

def fw_raw_path(framework_id):
    return f"data/01_raw/framework/{framework_id}_chothia.pdb"

def fw_hlt_path(framework_id):
    return f"data/02_intermediate/framework/{framework_id}_HLT.pdb"

def tg_raw_path(target_id):
    return f"data/01_raw/target/{target_id}.pdb"

def tg_raw_path_nochains(target_id, config):
    return f"data/01_raw/target/{config['targets'][target_id]['save_filename']}"

def tg_processed_path(target_id):
    return f"data/02_intermediate/targets/{target_id}/target_processed.pdb"

def merge_dicts(a, b):
    out = dict(a)
    out.update(b)
    return out

def run_cfg(config, run_id):
    runs = config.get("runs", {})
    exps = config.get("experiments", {})
    r = runs[run_id]
    exp = exps.get(r.get("experiment", ""), {})
    merged = _merge_dicts(exp, r)  # run overrides experiment
    return merged


