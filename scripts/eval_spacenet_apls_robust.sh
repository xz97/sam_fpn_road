#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scripts/eval_spacenet_apls_robust.sh save/spacenet_toponet_16x16_stageB_cldice /mnt/data/outputs/apls.log
OUT_DIR="${1:?OUT_DIR required, e.g. save/spacenet_toponet_16x16_stageB_cldice}"
LOG="${2:-/tmp/spacenet_apls.log}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MET="$ROOT/spacenet_metrics"

echo "[INFO] ROOT=$ROOT" | tee "$LOG"
echo "[INFO] OUT_DIR=$OUT_DIR" | tee -a "$LOG"
echo "[INFO] MET=$MET" | tee -a "$LOG"

# sanity
test -d "$ROOT/$OUT_DIR/graph" || { echo "[ERR] missing $ROOT/$OUT_DIR/graph" | tee -a "$LOG"; exit 2; }

# ensure output dir
mkdir -p "$ROOT/$OUT_DIR/results/apls"

# locate go module (try common locations)
GO_DIR=""
if [ -d "$MET/apls" ] && [ -f "$MET/apls/go.mod" ]; then
  GO_DIR="$MET/apls"
elif [ -d "$MET/apls/src" ] && [ -f "$MET/apls/src/go.mod" ]; then
  GO_DIR="$MET/apls/src"
fi

if [ -z "$GO_DIR" ]; then
  echo "[ERR] Cannot find go.mod for spacenet apls under $MET/apls" | tee -a "$LOG"
  echo "[HINT] run: find spacenet_metrics -name go.mod -o -name main.go" | tee -a "$LOG"
  exit 3
fi

echo "[INFO] GO_DIR=$GO_DIR" | tee -a "$LOG"

# ensure go deps
( cd "$GO_DIR" && go mod tidy ) >>"$LOG" 2>&1 || true

# Get list of tiles from existing graphs (proposal graphs)
# Graph filenames are like AOI_2_Vegas_505.p
mapfile -t PGRAPHS < <(ls -1 "$ROOT/$OUT_DIR/graph/"*.p 2>/dev/null | sort)
echo "[INFO] prop_graph_count=${#PGRAPHS[@]}" | tee -a "$LOG"

# Derive GT graph path candidates.
# In sam_road spacenet folder, GT graphs often exist as:
#   spacenet/RGB_1.0_meter/<tile>__gt_graph.p
# If your GT path differs, adjust GT_ROOT below.
GT_ROOT="$ROOT/spacenet/RGB_1.0_meter"
test -d "$GT_ROOT" || { echo "[ERR] missing GT_ROOT=$GT_ROOT" | tee -a "$LOG"; exit 4; }

# temp json
GT_JSON="/tmp/gt.json"
PR_JSON="/tmp/prop.json"

ok=0
miss_gt=0
miss_prop=0

for pg in "${PGRAPHS[@]}"; do
  base="$(basename "$pg" .p)"          # AOI_2_Vegas_505
  gt="$GT_ROOT/${base}__gt_graph.p"

  if [ ! -f "$gt" ]; then
    ((miss_gt+=1))
    continue
  fi
  if [ ! -f "$pg" ]; then
    ((miss_prop+=1))
    continue
  fi

  echo "==== $base ====" | tee -a "$LOG"

  # convert pickle->json
  python3 "$MET/apls/convert.py" "$gt" "$GT_JSON" >>"$LOG" 2>&1
  python3 "$MET/apls/convert.py" "$pg" "$PR_JSON" >>"$LOG" 2>&1

  # run go apls
  ( cd "$GO_DIR" && go run . "$GT_JSON" "$PR_JSON" "$ROOT/$OUT_DIR/results/apls/${base}.txt" ) >>"$LOG" 2>&1

  ((ok+=1))
done

echo "[INFO] ok=$ok miss_gt=$miss_gt miss_prop=$miss_prop" | tee -a "$LOG"

# summarize
python3 "$MET/apls.py" --dir "$OUT_DIR" 2>&1 | tee -a "$LOG"

echo "[DONE] wrote: $ROOT/$OUT_DIR/results/apls/*.txt" | tee -a "$LOG"
