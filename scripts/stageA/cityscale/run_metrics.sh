#!/usr/bin/env bash
set -euo pipefail

SAVE_DIR="${1:?Usage: run_metrics.sh <SAVE_DIR>, e.g. save/cityscale_toponet_8x8_best}"
cd "$(dirname "$0")/../../.."   # repo root

echo "[INFO] repo_root=$(pwd)"
echo "[INFO] SAVE_DIR=${SAVE_DIR}"

# A) APLS: run go-based pipeline (generates results/apls/*.txt)
bash scripts/stageA/cityscale/run_metrics_apls.sh "${SAVE_DIR}"

# B) TOPO: we do NOT re-run topo generation here (it is slow and path-sensitive).
# We only summarize from existing results/topo/*.txt (paper-like micro summary).
python3 -u scripts/stageA/cityscale/summarize_topo.py --save_dir "${SAVE_DIR}"

# C) APLS summarize (skip NaN tiles)
python3 -u scripts/stageA/cityscale/summarize_apls.py --save_dir "${SAVE_DIR}"

# D) One-line CSV summary into results/
python3 -u scripts/stageA/cityscale/summarize_to_csv.py --save_dir "${SAVE_DIR}"

echo "[OK] metrics done: ${SAVE_DIR}"
