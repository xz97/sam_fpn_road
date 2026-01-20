#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash scripts/eval_cityscale_apls.sh save/<SAVE_DIR_NAME>"
  echo "Example: bash scripts/eval_cityscale_apls.sh save/cityscale_toponet_8x8_best"
  exit 1
fi

SAVE_DIR="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PRED_P_DIR="${REPO_ROOT}/${SAVE_DIR}/graph"
GT_P_DIR="${REPO_ROOT}/cityscale/20cities"

OUT_DIR="${REPO_ROOT}/${SAVE_DIR}/results/apls"
JSON_DIR="${OUT_DIR}/json"
mkdir -p "$OUT_DIR" "$JSON_DIR"

echo "[INFO] pred_p_dir = $PRED_P_DIR"
echo "[INFO] gt_p_dir   = $GT_P_DIR"
echo "[INFO] out_dir    = $OUT_DIR"

# 逐 tile：GT pickle + Pred pickle -> json -> Go APLS -> txt
shopt -s nullglob
pred_files=("$PRED_P_DIR"/*.p)
echo "[INFO] pred tiles = ${#pred_files[@]}"

for pred_p in "${pred_files[@]}"; do
  id="$(basename "$pred_p" .p)"
  gt_p="${GT_P_DIR}/region_${id}_refine_gt_graph.p"

  if [[ ! -f "$gt_p" ]]; then
    echo "[WARN] missing GT pickle for tile ${id}: $gt_p ; skip"
    continue
  fi

  gt_json="${JSON_DIR}/gt_${id}.json"
  pr_json="${JSON_DIR}/pr_${id}.json"
  out_txt="${OUT_DIR}/${id}.txt"

  python3 -u cityscale_metrics/apls/convert.py "$gt_p" "$gt_json"
  python3 -u cityscale_metrics/apls/convert.py "$pred_p" "$pr_json"

  # 注意：CityScale 的 main.go 不支持 -h；并且 len(os.Args)>4 会启用 small-tile 参数
  # 为了不改代码，我们给一个占位参数 "small" 来触发该分支
  GO111MODULE=off go run cityscale_metrics/apls/main.go "$gt_json" "$pr_json" "$out_txt" small >/dev/null

  echo "[OK] tile ${id} -> ${out_txt}"
done

# 汇总（不改 baseline apls.py；我们用新脚本汇总 txt）
python3 -u scripts/summarize_cityscale_apls_txt.py \
  --apls_txt_dir "${OUT_DIR}" \
  --save_dir "${REPO_ROOT}/${SAVE_DIR}" \
  | tee "${REPO_ROOT}/${SAVE_DIR}/results_apls.txt"
