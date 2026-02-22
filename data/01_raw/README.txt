## Important !! ## 
due to the limitations by the rule setting and workflow config ID matching from snakemake,
files might be duplicated in order to accomodate using different target IDs (e.g. different chains for the same target protein)
As such, in the "raw" folder, CD33_7AW6_A and CD33_7AW6_B are both the same protein sequence and structure,
Differences will only start occuring in the processed files in 02_intermediate/target

This is done *explicitly and on purpouse* to avoid too many shenanigans with target_id wildcard cropping and regex that might lead to unwanted behaviour.
