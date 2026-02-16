from __future__ import annotations
import argparse
import os
from typing import Dict, Optional
from Bio.PDB import PDBParser
from Bio.PDB.DSSP import DSSP
import pandas as pd

if 'LIBCIFPP_DATA_DIR' not in os.environ:
    os.environ["LIBCIFPP_DATA_DIR"] = r"C:\Users\JV11_DK2\AppData\Local\anaconda3\envs\ada\share\libcifpp"

# MaxASA (Å^2) for RSA normalisation (Tien et al. 2013; widely used)
MAX_ASA: Dict[str, int] = {
    "A": 129, "R": 274, "N": 195, "D": 193, "C": 167,
    "Q": 225, "E": 223, "G": 104, "H": 224, "I": 197,
    "L": 201, "K": 236, "M": 224, "F": 240, "P": 159,
    "S": 155, "T": 172, "W": 285, "Y": 263, "V": 174,
}

AA_MAP = {'A': 'ALA','C': 'CYS','D': 'ASP','E': 'GLU',
          'F': 'PHE','G': 'GLY','H': 'HIS','I': 'ILE',
          'K': 'LYS','L': 'LEU','M': 'MET','N': 'ASN',
          'P': 'PRO','Q': 'GLN','R': 'ARG','S': 'SER',
          'T': 'THR','V': 'VAL','W': 'TRP','Y': 'TYR'}

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("-i", "--input", type=str, required=True, help="Input structure file (PDB)")
    p.add_argument("--pdb_id", type=str, required=False)
    p.add_argument("--model_number", type=int, default=0)
    # QoL: write results
    p.add_argument("--out_csv", type=str, default=None, help="Write per-residue DSSP table to CSV")
    p.add_argument('--chains', type=str, default="", help="Comma-separated chains to keep, e.g. A,B")
    p.add_argument("--which_dssp", type=str, default="mkdssp", help="Path/name of mkdssp executable")
    return p.parse_args()

def do_dssp(input_path: str, pdb_id: Optional[str]=None,
            model_number: int = 0, which_dssp: str = "mkdssp"):
    """

    Args:
        input_path:
        pdb_id:
        model_number:

    Returns:

    """
    p = PDBParser()
    if pdb_id is None:
        pdb_id = os.path.basename(input_path).split('.')[0]
    structure = p.get_structure(pdb_id, input_path)
    try:
        model = structure[model_number]
    except KeyError as e:
        raise KeyError(f"Model {model_number} not found in structure. Available models: {[m.id for m in structure]}") from e

    # fix for windows run...

    return DSSP(model, input_path, dssp=which_dssp)


def dssp_to_df(dssp: DSSP, chains: str=None):
    """
    Takes a dssp output and parses it into a dataframe
    Args:
        dssp:

    Returns:

    """
    MAX_ASA = dssp.residue_max_acc
    ls = [{
            'chain': chain_info[0],
            'res_number': chain_info[1][1],
            'dssp_id': res_info[0],
            'aa': res_info[1],
            'ss': res_info[2],
            'rsa': res_info[3],
            'asa': res_info[3] * MAX_ASA[AA_MAP[res_info[1]]], # RSA = ASA/Max ASA -> ASA = RSA * MaxASA
            'phi': res_info[4],
            'psi': res_info[5]}
          for chain_info, res_info in dssp.property_dict.items()]
    if chains is not None:
        return pd.DataFrame(ls).query('chain in @chains')
    else:
        return pd.DataFrame(ls)


def main():
    args = parse_args()
    chains = {c.strip() for c in args.chains.split(",") if c.strip()} or None
    dssp = do_dssp(args.input, args.pdb_id, args.model_number, args.which_dssp)
    dssp_df = dssp_to_df(dssp, chains)
    if args.out_csv is None:
        args.out_csv = os.path.join(os.path.dirname(args.input), f"{os.path.basename(args.input).split('.')[0]}_dssp.csv")
    dssp_df.to_csv(args.out_csv)
    return 0

if __name__=="__main__":
    main()
