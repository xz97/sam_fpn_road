#!/usr/bin/env bash
set -euo pipefail

source ~/venvs/road/bin/activate
cd ~/repos/sam_road
export PYTHONPATH="$(pwd):$PYTHONPATH"

RUN_NAME="${1:-20260115_stageA_spacenet_baseline_A10G}"
RUN_DIR="/mnt/data/outputs/${RUN_NAME}"
mkdir -p "${RUN_DIR}"

git rev-parse HEAD | tee "${RUN_DIR}/git_commit.txt"

CUDA_VISIBLE_DEVICES=0 python -u train.py \
  --config config/toponet_vitb_256_spacenet.yaml \
  --precision 16 \
  2>&1 | tee "${RUN_DIR}/train.log"
