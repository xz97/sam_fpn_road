#!/usr/bin/env bash
set -euo pipefail

SAVE_DIR="${1:?Usage: $0 <save_dir e.g. save/cityscale_toponet_8x8_best>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRED_P_DIR="${REPO_ROOT}/${SAVE_DIR}/graph"
GT_DIR="${REPO_ROOT}/cityscale/20cities"
OUT_DIR="${REPO_ROOT}/${SAVE_DIR}/results/apls"

mkdir -p "${OUT_DIR}/pred_json" "${OUT_DIR}/gt_json"

echo "[INFO] pred_p_dir = ${PRED_P_DIR}"
echo "[INFO] gt_dir     = ${GT_DIR}"
echo "[INFO] out_dir    = ${OUT_DIR}"

shopt -s nullglob
P_LIST=("${PRED_P_DIR}"/*.p)
echo "[INFO] pred tiles = ${#P_LIST[@]}"

# convert + go eval per tile
for f in "${P_LIST[@]}"; do
  id="$(basename "$f" .p)"
  gt_pkl="${GT_DIR}/region_${id}_graph_gt.pickle"

  if [ ! -f "${gt_pkl}" ]; then
    echo "[WARN] missing gt: ${gt_pkl} (skip ${id})"
    continue
  fi

  # 1) pred .p -> json
  python3 -u "${REPO_ROOT}/cityscale_metrics/apls/convert.py" \
    "${f}" \
    "${OUT_DIR}/pred_json/${id}.json"

  # 2) gt .pickle -> json
  python3 -u "${REPO_ROOT}/cityscale_metrics/apls/convert.py" \
    "${gt_pkl}" \
    "${OUT_DIR}/gt_json/${id}.json"

  # 3) go run -> txt (write into OUT_DIR)
  (
    cd "${REPO_ROOT}/cityscale_metrics/apls"
    go run . \
      "../../${SAVE_DIR}/results/apls/gt_json/${id}.json" \
      "../../${SAVE_DIR}/results/apls/pred_json/${id}.json" \
      "../../${SAVE_DIR}/results/apls/${id}.txt" \
      small
  ) || {
    echo "[WARN] go apls failed on tile ${id} (skip)"
    continue
  }

  echo "[OK] ${id}.txt"
done

echo "[DONE] outputs in ${OUT_DIR}"
