#!/usr/bin/env python3
import argparse
import math
import os
from typing import Optional, Set, Tuple, Dict, List

import pandas as pd

"""
This script parses a target PDB file (raw pdb),
trims it and removes ligands so that RFantibody can run.
Ligands and occluded residues (e.g. bound by or near ligands (Threshold<=4Å)
are marked in the REMARK section of the processed pdb file.
Also marks residues that are potentially available as hotspots based on DSSP RSA computed values

Additions:
- Optional DSSP CSV input (from run_dssp.py) to suggest "hotspot" residues:
  rsa > threshold AND not occluded by ligand (as defined by this script).
"""

WATER_RESNAMES = {"HOH", "WAT", "H2O", "DOD"}


def _safe_pad(line: str, n: int = 80) -> str:
    line = line.rstrip("\n")
    return line + (" " * max(0, n - len(line)))


def _remark_line(payload: str, remark_no: int = 900) -> str:
    # single line, no wrapping
    return f"REMARK {remark_no:3d} {payload}".rstrip()


def _parse_atom_line(line: str):
    line = _safe_pad(line, 80)
    rec = line[0:6]
    if rec not in ("ATOM  ", "HETATM"):
        return None
    atom_name = line[12:16].strip()
    altloc = line[16]
    resn = line[17:20].strip()
    chain = (line[21].strip() or " ")
    try:
        resseq = int(line[22:26])
    except ValueError:
        return None
    icode = line[26]
    try:
        x = float(line[30:38])
        y = float(line[38:46])
        z = float(line[46:54])
    except ValueError:
        return None
    element = (line[76:78].strip() if len(line) >= 78 else "").strip()
    return {"rec": rec, "atom_name": atom_name, "altloc": altloc, "resn": resn, "chain": chain, "resseq": resseq,
        "icode": icode, "x": x, "y": y, "z": z, "element": element, "raw": line.rstrip("\n"), }


def _chain_sort_key(ch: str) -> tuple:
    return (1, "") if ch == " " else (0, ch)


def _load_dssp_csv(dssp_csv: str) -> pd.DataFrame:
    """
    Expects the CSV format produced by run_dssp.py:
      chain, res_number, aa, ss, rsa, asa, ...
    """
    df = pd.read_csv(dssp_csv)

    # Normalise expected column names
    if "res_number" not in df.columns:
        raise ValueError(f"DSSP CSV missing required column 'res_number': {dssp_csv}")
    if "chain" not in df.columns:
        raise ValueError(f"DSSP CSV missing required column 'chain': {dssp_csv}")
    if "rsa" not in df.columns:
        raise ValueError(f"DSSP CSV missing required column 'rsa': {dssp_csv}")

    df["chain"] = df["chain"].astype(str).str.strip().replace({"": " "})
    df["res_number"] = df["res_number"].astype(int)
    df["rsa"] = pd.to_numeric(df["rsa"], errors = "coerce")

    # Optional fields
    if "aa" in df.columns:
        df["aa"] = df["aa"].astype(str).str.strip()
    if "asa" in df.columns:
        df["asa"] = pd.to_numeric(df["asa"], errors = "coerce")

    return df


def clean_pdb_for_rfantibody(in_path: str, out_path: str, chains: Optional[Set[str]] = None,
                             ligands: Optional[Set[str]] = None,  # e.g. {"FVP","NAG"}
                             ligand_cutoff: float = 4.0, renumber: bool = True, keep_altloc: str = "A", drop_h: bool = True,
                             dssp_csv: Optional[str] = None, rsa_threshold: Optional[float] = None, ) -> None:
    original_remarks: List[str] = []
    link_lines: List[str] = []

    protein_atoms: List[dict] = []
    ligand_atoms: List[dict] = []

    seen_model = False

    # For renumbering (output only)
    new_resseq: Dict[Tuple[str, int, str], int] = {}
    current_new: Dict[str, int] = {}

    def accept_altloc(altloc: str) -> bool:
        return altloc in (" ", keep_altloc)

    def is_h(atom: dict) -> bool:
        if atom["element"].upper() == "H":
            return True
        return atom["atom_name"].startswith("H")

    # Pass 1: keep REMARK, collect LINK, collect protein ATOM + ligand HETATM coords
    with open(in_path, "r", encoding = "utf-8", errors = "replace") as f:
        for raw in f:
            rec = raw[0:6]

            if rec.startswith("MODEL"):
                if seen_model:
                    continue
                seen_model = True
                continue

            if rec.startswith("ENDMDL"):
                break

            if rec == "REMARK":
                original_remarks.append(raw.rstrip("\n"))
                continue

            if rec == "LINK  ":
                link_lines.append(raw.rstrip("\n"))
                continue

            parsed = _parse_atom_line(raw)
            if parsed is None:
                continue

            if not accept_altloc(parsed["altloc"]):
                continue

            if drop_h and is_h(parsed):
                continue

            if parsed["rec"] == "ATOM  ":
                if chains is not None and parsed["chain"] not in chains:
                    continue
                # normalise altloc to blank in raw output line
                parsed["raw"] = parsed["raw"][:16] + " " + parsed["raw"][17:]
                protein_atoms.append(parsed)

            elif parsed["rec"] == "HETATM":
                if parsed["resn"] in WATER_RESNAMES:
                    continue
                if ligands is not None and parsed["resn"] not in ligands:
                    continue
                ligand_atoms.append(parsed)

    # Compute per-residue min distance + which ligand residue gives that min distance
    # protein residue id: (chain, resseq, icode, resn)
    # ligand residue id:  (resn, chain, resseq, icode)
    res_best: Dict[Tuple[str, int, str, str], Tuple[float, Tuple[str, str, int, str]]] = {}

    # pre-pack ligand coords with ligand residue identity
    lig_xyz = [(a["x"], a["y"], a["z"], (a["resn"], a["chain"], a["resseq"], a["icode"])) for a in ligand_atoms]

    for a in protein_atoms:
        rid = (a["chain"], a["resseq"], a["icode"], a["resn"])
        best_d = res_best.get(rid, (1e9, ("", "", -1, "")))[0]
        best_lrid = res_best.get(rid, (1e9, ("", "", -1, "")))[1]

        ax, ay, az = a["x"], a["y"], a["z"]
        for lx, ly, lz, lrid in lig_xyz:
            dx = ax - lx
            dy = ay - ly
            dz = az - lz
            d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if d < best_d:
                best_d = d
                best_lrid = lrid

        res_best[rid] = (best_d, best_lrid)

    # Extra REMARKS
    extra_remarks: List[str] = []

    # 1) LINK lines -> two REMARK lines each (explicit newline each time)
    for l in link_lines:
        extra_remarks.append(_remark_line("RFANTIBODY_LIGAND_LINK LINK", 900))
        rest = l[6:].rstrip("\n")
        extra_remarks.append(_remark_line(rest.lstrip(), 900))

    # 2) Occlusion lines -> two REMARK lines per residue
    contact_items = []
    for (chain, resseq, icode, resn), (d, (lresn, lchain, lresseq, licode)) in res_best.items():
        if d <= ligand_cutoff and lresn:
            contact_items.append(((chain, resseq, icode, resn), d, (lresn, lchain, lresseq, licode)))

    # Sort by chain then residue number (then insertion code), not by distance
    contact_items.sort(key = lambda x: (_chain_sort_key(x[0][0]), x[0][1], x[0][2], x[1],))

    # Build a simple "occluded" set for hotspot filtering (ignore insertion code for DSSP matching)
    occluded_simple: Set[Tuple[str, int]] = set()

    for (chain, resseq, icode, resn), d, (lresn, lchain, lresseq, licode) in contact_items:
        ic = icode.strip()
        lic = licode.strip()
        extra_remarks.append(_remark_line("RFANTIBODY_OCCLUDED_RES", 900))
        extra_remarks.append(
                _remark_line(f"{resn} {chain}{resseq}{ic} min_dist={d:.2f}A {lresn} {lchain}{lresseq}{lic}", 900))
        occluded_simple.add((chain, resseq))

    # 3) Hotspot suggestions from DSSP (rsa > threshold AND not occluded)
    if dssp_csv is not None and rsa_threshold is not None:
        ddf = _load_dssp_csv(dssp_csv)
        if renumber:
            # Sort for deterministic renumbering
            ddf = ddf.sort_values(by = ["chain", "res_number"], kind = "mergesort")

            new_numbers = []
            for chain, sub in ddf.groupby("chain", sort = False):
                mapping = {old_res: i + 1 for i, old_res in enumerate(sorted(sub["res_number"].unique()))}
                new_numbers.extend(sub["res_number"].map(mapping))

            ddf["res_number"] = new_numbers
        # If chains filter is active, apply it here too
        if chains is not None:
            ddf = ddf[ddf["chain"].isin(chains)]

        # Candidate = RSA above threshold AND not occluded
        # (Occlusion is defined by this script, not by RSA.)
        ddf = ddf[ddf["rsa"].notna()]
        cand = ddf[ddf["rsa"] > float(rsa_threshold)].copy()
        cand["is_occluded"] = cand.apply(lambda r: (r["chain"], int(r["res_number"])) in occluded_simple, axis = 1)
        cand = cand[~cand["is_occluded"]]

        # Sort by chain then residue number
        cand = cand.sort_values(by = ["chain", "res_number"],
                key = lambda s: s.map(lambda x: _chain_sort_key(str(x)) if s.name == "chain" else x),
                kind = "mergesort", )

        for _, r in cand.iterrows():
            chain = str(r["chain"]).strip() or " "
            resn_3 = str(r["aa"]).strip() if "aa" in cand.columns else ""
            resnum = int(r["res_number"])
            rsa = float(r["rsa"])

            # Optional ASA
            asa_str = ""
            if "asa" in cand.columns and pd.notna(r.get("asa", None)):
                asa_str = f" asa={float(r['asa']):.2f}"
            else:
                asa_str = ""

            extra_remarks.append(_remark_line("RFANTIBODY_HOTSPOT_RES", 900))
            if resn_3:
                extra_remarks.append(_remark_line(f"{resn_3} {chain}{resnum} rsa={rsa:.4f}{asa_str}", 900))
            else:
                extra_remarks.append(_remark_line(f"{chain}{resnum} rsa={rsa:.4f}{asa_str}", 900))

    # Renumber residues in output ATOM lines if requested
    out_atom_lines: List[str] = []
    for a in protein_atoms:
        line = a["raw"]
        chain_id = (line[21].strip() or " ")
        try:
            resseq = int(line[22:26])
        except ValueError:
            continue
        icode = line[26]

        if renumber:
            key = (chain_id, resseq, icode)
            if key not in new_resseq:
                current_new[chain_id] = current_new.get(chain_id, 0) + 1
                new_resseq[key] = current_new[chain_id]
            new_num = new_resseq[key]
            line = line[:22] + f"{new_num:4d}" + line[26:]

        out_atom_lines.append(line)

    # Add TER between chain changes + final TER/END
    final_atom_lines: List[str] = []
    prev_chain = None
    for l in out_atom_lines:
        ch = l[21] if len(l) > 21 else " "
        if prev_chain is None:
            prev_chain = ch
        elif ch != prev_chain:
            final_atom_lines.append("TER")
            prev_chain = ch
        final_atom_lines.append(l)

    if final_atom_lines:
        final_atom_lines.append("TER")

    if chains is not None:
        basename, dirname = os.path.basename(out_path), os.path.dirname(out_path)
        basename, extension = os.path.splitext(basename)
        bn = basename + f"_chains_{'_'.join(sorted(chains))}"
        out_path = os.path.join(dirname, bn + extension)

    with open(out_path, "w", encoding = "utf-8") as f:
        for r in original_remarks:
            f.write(r + "\n")
        for r in extra_remarks:
            f.write(r + "\n")
        for a in final_atom_lines:
            f.write(a + "\n")
        f.write("END\n")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("-i", "--input", required = True)
    p.add_argument("-o", "--output", required = True)
    p.add_argument("--chains", default = "", help = "Comma-separated chains to keep, e.g. A,B")
    p.add_argument("--ligands", default = "", help = "Comma-separated ligand resnames to consider, e.g. FVP,NAG")
    p.add_argument("--cutoff", type = float, default = 4.0, help = "Å cutoff for occlusion marking (default 4.0)")
    p.add_argument("--renumber", action = "store_true",
                   help = "Renumber the residues from author-numbering to starting from 1 (default False)")
    p.add_argument("--keep-h", action = "store_true", help = "Keep hydrogens")
    p.add_argument("--altloc", default = "A")

    # DSSP-based hotspot suggestions
    p.add_argument("--dssp_csv", default = None, help = "CSV produced by run_dssp.py")
    p.add_argument("--rsa_threshold", type = float, default = 0.2, help = "Hotspot RSA threshold (e.g. 0.25)")

    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    chains = {c.strip() for c in args.chains.split(",") if c.strip()} or None
    ligands = {x.strip().upper() for x in args.ligands.split(",") if x.strip()} or None

    clean_pdb_for_rfantibody(in_path = args.input, out_path = args.output, chains = chains, ligands = ligands,
            ligand_cutoff = args.cutoff, renumber = args.renumber, keep_altloc = args.altloc, drop_h = not args.keep_h,
            dssp_csv = args.dssp_csv, rsa_threshold = args.rsa_threshold, )
