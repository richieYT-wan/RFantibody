"job" bash scripts are generated here from RFantibody/scripts/util/make_quiver_script.sh
using various inputs ex:

# This creates the scripts based on a summed RSA threshold of s(RSA)>1.785, counting from position A149 for a given input and target.
bash scripts/util/make_patch_quiver_script.sh -f inputs/framework/processed/7eow_HLT.pdb -t inputs/target/processed/CD33_7AW6_processed_chains_A.pdb -T 1.785 -c 0 -S A149