#!/usr/bin/env python3
import argparse
from typing import Optional, Set, Tuple, Dict


def clean_pdb(infile:str, outfile:str, chain_ids: Optional[Set[str]] = None,
              renumber: bool = True, drop_h: bool = True, drop_links: bool = True,
              keep_altloc:str = "A") -> None:
    """
    Args:
        infile:
        outfile:
        chain_ids:
        renumber:
        drop_h:
        drop_links:
        keep_altloc:

    Returns:
    """
    out_lines = []
    pass



def clean_pdb_gpt(
    in_path: str,
    out_path: str,
    chains: Optional[Set[str]] = None,
    renumber: bool = True,
    drop_h: bool = True,
    keep_altloc: str = "A") -> None:
    """
    """
    out_lines = []

    seen_model = False
    new_resseq: Dict[Tuple[str, int, str], int] = {}
    current_new: Dict[str, int] = {}

    def keep_line(line: str) -> Optional[str]:
        nonlocal seen_model

        rec = line[0:6]

        # Keep only first MODEL if present
        if rec.startswith("MODEL"):
            if seen_model:
                return None  # ignore subsequent models
            seen_model = True
            return None

        if rec.startswith("ENDMDL"):
            # stop after first model
            raise StopIteration

        if rec not in ("ATOM  ", "HETATM"):
            return None

        # Drop all HETATM (waters/ligands/ions)
        if rec == "HETATM":
            return None

        chain_id = (line[21].strip() or " ")
        if chains is not None and chain_id not in chains:
            return None

        # AltLoc handling (column 17, index 16)
        altloc = line[16]
        if altloc not in (" ", keep_altloc):
            return None

        # Drop hydrogens (best-effort)
        element = line[76:78].strip().upper() if len(line) >= 78 else ""
        atom_name = line[12:16].strip()
        if drop_h and (element == "H" or atom_name.startswith("H")):
            return None

        # Normalise altloc to blank
        line = line[:16] + " " + line[17:]

        # Renumber residues per chain starting from 1
        if renumber:
            try:
                resseq = int(line[22:26])
            except ValueError:
                return None
            icode = line[26]  # insertion code
            key = (chain_id, resseq, icode)
            if key not in new_resseq:
                current_new[chain_id] = current_new.get(chain_id, 0) + 1
                new_resseq[key] = current_new[chain_id]
            new_num = new_resseq[key]
            line = line[:22] + f"{new_num:4d}" + line[26:]

        return line.rstrip("\n")

    try:
        with open(in_path, "r", encoding="utf-8", errors="replace") as f:
            for raw in f:
                try:
                    kept = keep_line(raw)
                except StopIteration:
                    break
                if kept is not None:
                    out_lines.append(kept)
    except FileNotFoundError as e:
        raise SystemExit(f"Input file not found: {e.filename}")

    # Add TER between chain changes + final TER/END
    final_lines = []
    prev_chain = None
    for l in out_lines:
        chain = l[21] if len(l) > 21 else " "
        if prev_chain is None:
            prev_chain = chain
        elif chain != prev_chain:
            final_lines.append("TER")
            prev_chain = chain
        final_lines.append(l)

    if final_lines:
        final_lines.append("TER")
    final_lines.append("END")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(final_lines) + "\n")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Clean a PDB for RFantibody-like pipelines.")
    p.add_argument("-i", "--input", required=True, help="Input PDB path")
    p.add_argument("-o", "--output",
                   required=False, help="Output cleaned PDB path")
    p.add_argument("--chains",
        default="",
        help="Comma-separated chain IDs to keep (e.g. 'A,B'). Empty = keep all.",
    )
    p.add_argument("--no-renumber", action="store_true", help="Do not renumber residues.")
    p.add_argument("--keep-h", action="store_true", help="Keep hydrogens if present.")
    p.add_argument(
        "--altloc",
        default="A",
        help="AltLoc identifier to keep (default: A). Always keeps blank as well.",
    )
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    chains = None
    if args.chains.strip():
        chains = {c.strip() for c in args.chains.split(",") if c.strip()}
    clean_pdb_gpt(
        in_path=args.input,
        out_path=args.output,
        chains=chains,
        renumber=not args.no_renumber,
        drop_h=not args.keep_h,
        keep_altloc=args.altloc,
    )
