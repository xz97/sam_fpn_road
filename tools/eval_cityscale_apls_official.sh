#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash tools/eval_cityscale_apls_official.sh <pred_dir> <log_path>
# Example:
#   bash tools/eval_cityscale_apls_official.sh save/save/cityscale_toponet_16x16_stageB_cldice /mnt/data/outputs/xxx.log

PRED_DIR="${1:?missing pred_dir (e.g. save/save/cityscale_toponet_16x16_stageB_cldice)}"
LOG="${2:-/mnt/data/outputs/$(date +%Y%m%d)_cityscale_apls_OFFICIALMODE.log}"

OFFICIAL_REPO="${OFFICIAL_REPO:-$HOME/repos/sam_road_official}"

source "$HOME/venvs/road/bin/activate

cd "${OFFICIAL_REPO}/cityscale_metrics"

# Hard fail if official compat script is missing
test -f ./apls_official_compat.bash || { echo "[ERR] missing apls_official_compat.bash in official repo"; exit 2; }

echo "[INFO] OFFICIAL_REPO=${OFFICIAL_REPO}" | tee "$LOG"
echo "[INFO] PRED_DIR=${PRED_DIR}" | tee -a "$LOG"
echo "[INFO] PWD=$(pwd)" | tee -a "$LOG"
echo "[INFO] go=$(command -v go) ; $(go version)" | tee -a "$LOG"

bash ./apls_official_compat.bash "${PRED_DIR}" 2>&1 | tee -a "$LOG"

echo "[OK] log saved: ${LOG}"
