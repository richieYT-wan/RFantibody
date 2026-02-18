import re

def sanitize(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
    s = re.sub(r"^_+|_+$", "", s)
    s = re.sub(r"_+", "_", s)
    return s

def get_framework_ids(config):
    return sorted(config.get("frameworks", {}).keys())

def get_target_ids(config):
    return sorted(config.get("targets", {}).keys())

def get_run_ids(config):
    return sorted(config.get("runs", {}).keys())

def get_patch_run_ids(config):
    return sorted(config.get("patch_runs", {}).keys())

def fw_raw_path(framework_id):
    return f"data/01_raw/frameworks/{framework_id}_chothia.pdb"

def fw_hlt_path(framework_id):
    return f"data/02_intermediate/frameworks/{framework_id}_HLT.pdb"

def tg_raw_path(target_id):
    return f"data/01_raw/targets/{target_id}.pdb"

def tg_processed_path(target_id):
    return f"data/02_intermediate/targets/{target_id}/target_processed.pdb"

def _merge_dicts(a, b):
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

def patch_run_cfg(config, patch_run_id):
    prs = config.get("patch_runs", {})
    exps = config.get("experiments", {})
    r = prs[patch_run_id]
    exp = exps.get(r.get("experiment", ""), {})
    merged = _merge_dicts(exp, r)
    return merged
