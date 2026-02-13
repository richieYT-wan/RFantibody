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
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd
from Bio.PDB import PDBParser
from Bio.SeqUtils import seq1

LABEL_RE = re.compile(r"^REMARK\s+PDBinfo-LABEL:\s*(\d+)\s+(\S+)\s*$")
SCORE_RE = re.compile(r"^SCORE\s+([^:]+):\s*(.+?)\s*$")


def read_lines(p: Path) -> List[str]:
    """Read file lines robustly across platforms/encodings."""
    return p.read_text(encoding="latin-1", errors="replace").splitlines()


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
        return (pd.NA, pd.NA)
    return (min(vals), max(vals))


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
    parser = PDBParser(QUIET=True)
    with pdb_path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        structure = parser.get_structure(pdb_path.stem, handle)

    chain_res: Dict[str, List[Tuple[int, str, str]]] = defaultdict(list)
    model = next(structure.get_models())

    for chain in model:
        for res in chain:
            hetflag, resseq, icode = res.id
            if hetflag != " ":
                continue
            try:
                aa = seq1(res.get_resname(), custom_map={"MSE": "M"})
            except Exception:
                aa = "X"
            chain_res[chain.id].append((resseq, str(icode).strip(), aa))

    seqs: Dict[str, str] = {}
    for ch, items in chain_res.items():
        items.sort(key=lambda x: (x[0], x[1]))
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

    df = pd.read_csv(scores_path, sep=sep, engine="python")
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

    df = df.rename(columns={best_col: "id"})
    df["id"] = df["id"].astype(str)
    df = df.drop_duplicates(subset=["id"], keep="first")

    return df


def parse_pdb_dir(pdb_dir: Path) -> pd.DataFrame:
    """
    Parse all PDB files in a directory and return a table with:
      id, vh, t, H1_start/end, H2_start/end, H3_start/end, plus any SCORE fields found.
    """
    pdbs = sorted(pdb_dir.glob("*.pdb"))
    if not pdbs:
        raise SystemExit(f"ERROR: No .pdb files found in: {pdb_dir}")

    rows: List[Dict[str, Any]] = []

    for pdb in pdbs:
        lines = read_lines(pdb)
        seqs = parse_sequences_from_pdb(pdb)
        labels = parse_labels(lines)
        scores = parse_scores_from_pdb(lines)

        h1s, h1e = label_range(labels, "H1")
        h2s, h2e = label_range(labels, "H2")
        h3s, h3e = label_range(labels, "H3")

        row: Dict[str, Any] = {
            "id": pdb.stem,
            "vh": seqs.get("H", ""),
            "t": seqs.get("T", ""),
            "H1_start": h1s, "H1_end": h1e,
            "H2_start": h2s, "H2_end": h2e,
            "H3_start": h3s, "H3_end": h3e,
            # keep full label map too (handy for debugging/collabs)
            "labels_json": json.dumps(labels),
        }
        row.update(scores)
        rows.append(row)

    df = pd.DataFrame(rows)

    # Put core columns first; keep remaining score columns afterwards
    core = ["id", "vh", "t", "H1_start", "H1_end", "H2_start", "H2_end", "H3_start", "H3_end", "labels_json"]
    rest = [c for c in df.columns if c not in core]
    return df[core + rest]


def merge_scores(df: pd.DataFrame, scores_path: Path, pdb_stems: List[str]) -> pd.DataFrame:
    """
    Merge qvscorefile scores into df by 'id'. If the same score name exists in both,
    prefer the .sc value when present.
    """
    sc = read_scores_table(scores_path, pdb_stems)
    sc_cols = [c for c in sc.columns if c != "id"]

    merged = df.merge(sc, on="id", how="left", suffixes=("", "_sc"))

    # Prefer _sc when both exist
    for c in list(merged.columns):
        if c.endswith("_sc"):
            base = c[:-3]
            if base in merged.columns:
                merged[base] = merged[c].combine_first(merged[base])
                merged = merged.drop(columns=[c])
            else:
                merged = merged.rename(columns={c: base})

    return merged

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Parse RF2 output PDBs and scores into a single TSV/CSV.")
    p.add_argument("--pdb-dir", required=True, type=Path, help="Directory containing output .pdb files")
    p.add_argument("-o", "--outfile", required=True, type=Path, help="Output table (.tsv or .csv)")
    p.add_argument("--scores", type=Path, default=None, help="Optional .sc scores file (qvscorefile output)")
    p.add_argument('--framework', type=str, default=None, help="str identifier for the framework")
    p.add_argument('--target', type=str, default=None, help="str identifier for the target")
    p.add_argument('--hotspot', type=str, default=None, help="str identifier for the hotspots")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    pdb_dir = args.pdb_dir
    if not pdb_dir.is_dir():
        raise SystemExit(f"ERROR: --pdb-dir is not a directory: {pdb_dir}")

    df = parse_pdb_dir(pdb_dir)

    if args.scores is not None:
        if not args.scores.exists():
            raise SystemExit(f"ERROR: --scores file not found: {args.scores}")
        pdb_stems = [p.stem for p in sorted(pdb_dir.glob("*.pdb"))]
        df = merge_scores(df, args.scores, pdb_stems)

    args.outfile.parent.mkdir(parents=True, exist_ok=True)
    sep = "," if args.outfile.suffix.lower() == ".csv" else "\t"
    df.to_csv(args.outfile, sep=sep, index=False)


if __name__ == "__main__":
    main()
