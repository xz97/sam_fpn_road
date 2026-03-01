#!/usr/bin/env bash
set -euo pipefail

PRED_IN="${1:?Usage: $0 <PRED_DIR_ABS_OR_REL>}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MET_DIR="$REPO/cityscale_metrics"
TOPO_DIR="$MET_DIR/topo"
CITYSCALE_DATA_ROOT="/mnt/data/datasets/cityscale"

# resolve pred dir to abs
if [[ "$PRED_IN" = /* ]]; then
  PRED_DIR="$PRED_IN"
else
  PRED_DIR="$(cd "$REPO/$PRED_IN" && pwd)"
fi

test -d "$PRED_DIR/graph" || { echo "[ERROR] missing $PRED_DIR/graph"; exit 2; }

# (optional) bind dataset root under cityscale_metrics if needed by official code
mkdir -p "$MET_DIR"
ln -sfn "$CITYSCALE_DATA_ROOT" "$MET_DIR/cityscale" || true

# bind pred under cityscale_metrics for stable relative path
ln -sfn "$PRED_DIR" "$MET_DIR/_pred"

# logs dir
EVAL_DIR="$PRED_DIR/eval/topo"
mkdir -p "$EVAL_DIR"

echo "[TOPO] pred=$PRED_DIR"
echo "[TOPO] writing logs to $EVAL_DIR"
echo "[TOPO] metrics_dir=$MET_DIR"

# run per-tile topo (official)
cd "$TOPO_DIR"
python3 main.py -savedir "_pred" 2>&1 | tee "$EVAL_DIR/topo_main.log"

# robust summarize (fixed parser that ignores coordinate lines)
cd "$REPO"
python3 tools/summarize_cityscale_topo_fixed.py "$PRED_DIR" \
  2>&1 | tee "$EVAL_DIR/topo_summary_fixed.log"

echo "[TOPO] done."
echo "[TOPO] outputs:"
echo "  - $PRED_DIR/results/topo/*.txt"
echo "  - $EVAL_DIR/topo_main.log"
echo "  - $PRED_DIR/eval/topo/topo_summary_fixed.csv"
echo "  - $EVAL_DIR/topo_summary_fixed.log"
