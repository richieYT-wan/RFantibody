#!/bin/bash

curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc  # or ~/.zshrc if using zsh
bash include/download_weights.sh
uv sync
source .venv/bin/activate
rfdiffusion --help