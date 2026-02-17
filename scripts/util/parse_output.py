#!/usr/bin/env python3
"""
parse_output.py

Parse RF2 (and Quiver/RF2) output PDBs to produce a single table with:
- vh: heavy-chain sequence (chain 'H')
- t:  target sequence (chain 'T')
- H1/H2/H3 start/end from REMARK PDBinfo-LABEL lines
- scores:
    * in PDB mode: read from trailing "SCORE key: value" lines inside each PDB
    * in QV mode: read from qvscorefile-produced .sc table and merge by ID

Designed to be portable (Windows/Linux): always opens text as latin-1 with errors=replace.
"""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd
from Bio.PDB import PDBParser
from Bio.SeqUtils import seq1
from joblib import Parallel, delayed

LABEL_RE = re.compile(r"^REMARK\s+PDBinfo-LABEL:\s*(\d+)\s+(\S+)\s*$")
SCORE_RE = re.compile(r"^SCORE\s+([^:]+):\s*(.+?)\s*$")


def read_lines(p: Path) -> List[str]:
    """Read file lines robustly across platforms/encodings."""
    return p.read_text(encoding = "latin-1", errors = "replace").splitlines()


def normalise_colname(name: str) -> str:
    """Normalise score column names across sources."""
    s = str(name).strip().rstrip(":")
    s = re.sub(r"\s+", "_", s)
    return s


def parse_labels(lines: List[str]) -> Dict[str, List[int]]:
    """Parse REMARK PDBinfo-LABEL residue annotations into label -> sorted residue numbers."""
    labels: Dict[str, List[int]] = defaultdict(list)
    for ln in lines:
        m = LABEL_RE.match(ln)
        if m:
            resnum = int(m.group(1))
            label = m.group(2)
            labels[label].append(resnum)
    return {k: sorted(v) for k, v in labels.items()}


def label_range(labels: Dict[str, List[int]], label: str) -> Tuple[Any, Any]:
    """Return (min,max) for a label or (NA,NA)."""
    vals = labels.get(label)
    if not vals:
        return pd.NA, pd.NA
    return min(vals), max(vals)


def parse_scores_from_pdb(lines: List[str]) -> Dict[str, Any]:
    """
    Parse trailing SCORE lines in PDB:
      SCORE some_key: 1.234
    Returns dict key->value (float where possible).
    """
    scores: Dict[str, Any] = {}
    for ln in lines:
        m = SCORE_RE.match(ln)
        if not m:
            continue
        key = normalise_colname(m.group(1))
        val_s = m.group(2).strip()

        if val_s.lower() == "nan":
            val = float("nan")
        else:
            try:
                val = float(val_s)
            except ValueError:
                val = val_s

        scores[key] = val
    return scores


def parse_sequences_from_pdb(pdb_path: Path) -> Dict[str, str]:
    """
    Extract per-chain sequences from a PDB using Bio.PDB.
    Uses first model only; skips hetero residues.
    """
    parser = PDBParser(QUIET = True)
    with pdb_path.open("r", encoding = "latin-1", errors = "replace", newline = "") as handle:
        structure = parser.get_structure(pdb_path.stem, handle)

    chain_res: Dict[str, List[Tuple[int, str, str]]] = defaultdict(list)
    model = next(structure.get_models())

    for chain in model:
        for res in chain:
            hetflag, resseq, icode = res.id
            if hetflag != " ":
                continue
            try:
                aa = seq1(res.get_resname(), custom_map = {"MSE": "M"})
            except Exception:
                aa = "X"
            chain_res[chain.id].append((resseq, str(icode).strip(), aa))

    seqs: Dict[str, str] = {}
    for ch, items in chain_res.items():
        items.sort(key = lambda x: (x[0], x[1]))
        seqs[ch] = "".join(aa for _, _, aa in items)
    return seqs


def read_scores_table(scores_path: Path, pdb_stems: List[str]) -> pd.DataFrame:
    """
    Read the qvscorefile-produced .sc (TSV-ish). Auto-detect the ID column by matching PDB stems.
    Returns a DataFrame with 'id' plus normalised score columns.
    """
    # robust delimiter detection: tab if present, else whitespace
    first_line = read_lines(scores_path)[0] if scores_path.exists() else ""
    sep = "\t" if "\t" in first_line else r"\s+"

    df = pd.read_csv(scores_path, sep = sep, engine = "python")
    df.columns = [normalise_colname(c) for c in df.columns]

    stems_set = set(pdb_stems)

    # Pick the column with the most hits against extracted PDB stems
    best_col: Optional[str] = None
    best_hits = -1
    for c in df.columns:
        hits = df[c].astype(str).isin(stems_set).sum()
        if hits > best_hits:
            best_hits = hits
            best_col = c

    if best_col is None or best_hits <= 0:
        best_col = df.columns[0]  # fallback

    df = df.rename(columns = {best_col: "id"})
    df["id"] = df["id"].astype(str)
    df = df.drop_duplicates(subset = ["id"], keep = "first")

    return df


def parse_single_pdb(pdb: Path) -> Dict[str, Any]:
    """
    Parses a single PDB file at a time (wrapper for parallelisation to call in parse_pdb_dir)
    """
    lines = read_lines(pdb)
    seqs = parse_sequences_from_pdb(pdb)
    labels = parse_labels(lines)
    scores = parse_scores_from_pdb(lines)

    h1s, h1e = label_range(labels, "H1")
    h2s, h2e = label_range(labels, "H2")
    h3s, h3e = label_range(labels, "H3")
    # Formats the results into a dictionary to use for creating a df -> to csv
    row: Dict[str, Any] = {"id": pdb.stem,  # identifier in RFantibody run, e.g. its ID in produced by RFantibody
                           "vh": seqs.get("H", ""), "t": seqs.get("T", ""), "H1_start": h1s, "H1_end": h1e,
                           "H2_start": h2s, "H2_end": h2e, "H3_start": h3s, "H3_end": h3e,
                           # uncomment this to keep full label map too (handy for debugging)
                           # "labels_json": json.dumps(labels),
                           }
    row.update(scores)
    return row

    # wrapper = partial(cluster_single_threshold, dist_array=dist_array, features=features, labels=labels,
    #                       encoded_labels=encoded_labels, label_encoder=label_encoder,  #  #
    #                       silhouette_aggregation=silhouette_aggregation)  # results = Parallel(n_jobs=n_jobs)(  #
    #                       delayed(wrapper)(threshold=t) for t in tqdm(limits))


def parse_pdb_dir(pdb_dir: Path, n_jobs: int = -1) -> pd.DataFrame:
    """
    Parse all PDB files in a directory and return a table with:
      id, vh, t, H1_start/end, H2_start/end, H3_start/end, plus any SCORE fields found.
    """
    pdbs = sorted(pdb_dir.glob("*.pdb"))
    if not pdbs:
        raise SystemExit(f"ERROR: No .pdb files found in: {pdb_dir}")

    rows = Parallel(n_jobs = n_jobs)(delayed(parse_single_pdb)(pdb = pdb) for pdb in pdbs)
    df = pd.DataFrame(rows)

    # Put core columns first; keep remaining score columns afterwards
    core = ["id", "vh", "t", "H1_start", "H1_end", "H2_start", "H2_end", "H3_start", "H3_end"]  # , "labels_json"]
    rest = [c for c in df.columns if c not in core]
    return df[core + rest]


def merge_scores(df: pd.DataFrame, scores_path: Path, pdb_stems: List[str]) -> pd.DataFrame:
    """
    Merge qvscorefile scores into df by 'id'. If the same score name exists in both,
    prefer the .sc value when present.
    """
    sc = read_scores_table(scores_path, pdb_stems)
    sc_cols = [c for c in sc.columns if c != "id"]

    merged = df.merge(sc, on = "id", how = "left", suffixes = ("", "_sc"))

    # Prefer _sc when both exist
    for c in list(merged.columns):
        if c.endswith("_sc"):
            base = c[:-3]
            if base in merged.columns:
                merged[base] = merged[c].combine_first(merged[base])
                merged = merged.drop(columns = [c])
            else:
                merged = merged.rename(columns = {c: base})

    return merged


def parse_filename(filename: str) -> Dict[str]:
    """
    From a provided original filename, try to parse it into used arguments (framework, target, hotspot)
        Not perfect because some runs were done using pipeline_rfantibody.sh (contains command log)
        and others were run using test_pipeline_quiver/pdb.sh (no command log)
        but both share the same automatic filename system.
        When using auto filename mode on the pipelines, the framework, target and hotspots are logged.
    """

    fn = filename.lower()
    # in both auto and custom job mode, the first 14 characters are the script-generated timestamp in %y%m%d_%h%m%s
    res = {'timestamp': filename[:13].replace('_', '') if filename[:13].replace('_', '').isalnum() else None}
    # If all three identifiers from the autogenerated fn are found, can parse
    if fn.find('_fw') and fn.find('_tg') and fn.find('_hs'):
        res['framework'] = fn.split('_fw')[1].split('_tg')[0]
        res['target'] = fn.split('_tg')[1].split('_hs')[0]
        res['hotspots'] = fn.split('_hs')[1]
    # If can't find the identifiers, save the entire filename as job ID that can be retraced later
    else:
        res['job_id'] = filename

    return res


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description = "Parse RF2 output PDBs and scores into a single TSV/CSV.")
    p.add_argument("--pdb-dir", required = True, type = Path, help = "Directory containing output .pdb files")
    p.add_argument("--original_filename", required = True, type = str,
                   help = "original output folder filename used as identifier" \
                          "(either auto named by pipeline_rfantibody.sh or custom job name)")
    p.add_argument("-o", "--outfile", required = True, type = Path, help = "Output table (.tsv or .csv)")
    p.add_argument("--scores", type = Path, default = None, help = "Optional .sc scores file (qvscorefile output)")
    p.add_argument('--framework', type = str, default = None, help = "str identifier for the framework")
    p.add_argument('--target', type = str, default = None, help = "str identifier for the target")
    p.add_argument('--hotspot', type = str, default = None, help = "str identifier for the hotspots")
    p.add_argument('--n_jobs', type = int, default = -1, help = 'Parallelisation of PDB parsing (default: -1)')
    return p.parse_args()


def main() -> None:
    args = parse_args()
    pdb_dir = args.pdb_dir
    if not pdb_dir.is_dir():
        raise SystemExit(f"ERROR: --pdb-dir is not a directory: {pdb_dir}")

    df = parse_pdb_dir(pdb_dir, args.n_jobs)

    if args.scores is not None:
        if not args.scores.exists():
            raise SystemExit(f"ERROR: --scores file not found: {args.scores}")
        pdb_stems = [p.stem for p in sorted(pdb_dir.glob("*.pdb"))]
        df = merge_scores(df, args.scores, pdb_stems)

    args.outfile.parent.mkdir(parents = True, exist_ok = True)
    sep = "," if args.outfile.suffix.lower() == ".csv" else "\t"
    # Parsing filename identifiers and reordering columns
    cols = list(df.columns)
    identifiers = parse_filename(args.original_filename)
    reorder = list(identifiers.keys()) + cols
    for k, v in identifiers.items():
        df[k] = v
    df[reorder].rename(columns = {'id': 'rfab_id'}).to_csv(args.outfile, sep = ',', index = False)


if __name__ == "__main__":
    main()
