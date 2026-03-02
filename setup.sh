#!/bin/bash

echo "################################################"
echo "Installing RFantibody environment"
echo "################################################"

curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc  # or ~/.zshrc if using zsh
bash include/download_weights.sh
uv sync
source .venv/bin/activate
rfdiffusion --help

echo "################################################"
echo "Creating conda environment for processing"
echo "################################################"

echo
deactivate
conda env create -f workflows/envs/ada.yaml
