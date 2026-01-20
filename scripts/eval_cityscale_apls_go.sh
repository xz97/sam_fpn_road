#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <SAVE_DIR e.g. save/cityscale_toponet_8x8_best>"
  exit 1
fi

SAVE_DIR="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PRED_P_DIR="${REPO_ROOT}/${SAVE_DIR}/graph"
OUT_DIR="${REPO_ROOT}/${SAVE_DIR}/results/apls"
PRED_JSON_DIR="${OUT_DIR}/pred_json"

mkdir -p "${OUT_DIR}" "${PRED_JSON_DIR}"

echo "[INFO] pred_p_dir   = ${PRED_P_DIR}"
echo "[INFO] gt_dir       = ${REPO_ROOT}/cityscale/20cities"
echo "[INFO] out_dir      = ${OUT_DIR}"

# 1) Convert pred *.p -> pred_json/*.json
for f in "${PRED_P_DIR}"/*.p; do
  id="$(basename "$f" .p)"
  python3 -u "${REPO_ROOT}/cityscale_metrics/apls/convert.py" "$f" "${PRED_JSON_DIR}/${id}.json"
done

echo "[INFO] pred tiles   = $(ls -1 "${PRED_P_DIR}"/*.p | wc -l)"
echo "[INFO] pred json    = $(ls -1 "${PRED_JSON_DIR}"/*.json | wc -l)"

# 2) Run Go APLS per tile -> results/apls/<id>.txt
pushd "${REPO_ROOT}/cityscale_metrics/apls" >/dev/null

for j in "${PRED_JSON_DIR}"/*.json; do
  id="$(basename "$j" .json)"
  gt="${REPO_ROOT}/cityscale/20cities/region_${id}_gt_graph.json"
  out="${OUT_DIR}/${id}.txt"

  if [ ! -f "$gt" ]; then
    echo "[WARN] missing gt: $gt (skip ${id})"
    continue
  fi

  # main.go: args[1]=gt_json, args[2]=pred_json, args[3]=out_txt
  # If len(os.Args) > 4 => use "small tiles" params; we pass a dummy 4th arg: "small"
  go run . "$gt" "$j" "$out" small > /dev/null

  echo "[OK] tile ${id} -> $(basename "$out")"
done

popd >/dev/null

echo "[DONE] APLS txt files: $(ls -1 "${OUT_DIR}"/*.txt 2>/dev/null | wc -l)"
