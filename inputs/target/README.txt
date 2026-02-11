CD33_7AW6.pdb is downloaded to ./raw/ from RCSB using
curl -L -o CD33_7AW6.pdb "https://files.rcsb.org/download/7AW6.pdb"

processed files are created using RFantibody/scripts/util/pipeline_clean_target.sh
    - no renumbering (uses number amino acid numbering, e.g. sequence starts fx at 20 for chain A)
    - NAG,FVP as --ligands
    - with 4 Angstrom as the distance cutoff (--cutoff 4.0)
    - 0.4 as the RSA threshold (--threshold 0.4)
    - Either A, B or A,B for --chains

Infos for hotspot definitions
    Residue is marked (in processed file, under REMARK 900) as hotspot if:
        - RSA > 0.4
        - Not occluded (cutoff = 4.0 Angstrom)
    --> This is not perfect as residues near occluded residues might be marked as "available"

    Domain definitions:
    - Chain A:
        - V domain: A24-A139 (Author numbering), A35-A150 (UniProt)
        - linker:   A140-A148 (Author numbering)
        - C domain: A149-A225 (Author numbering), A160-A236 (UniProt)
    - Chain B:
        - V domain: B24-B139 (Author numbering)
        - linker:   B140-B148 (Author numbering)
        - C domain: B149-B225 (Author numbering)


