#!/usr/bin/env bash
set -euo pipefail

PRED_IN="${1:?Usage: $0 <PRED_DIR_ABS_OR_REL>}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MET_DIR="$REPO/spacenet_metrics"
TOPO_DIR="$MET_DIR/topo"
SPACENET_DATA_ROOT="/mnt/data/datasets/spacenet"

# resolve pred dir to abs
if [[ "$PRED_IN" = /* ]]; then
  PRED_DIR="$PRED_IN"
else
  PRED_DIR="$(cd "$REPO/$PRED_IN" && pwd)"
fi

test -d "$PRED_DIR/graph" || { echo "[ERROR] missing $PRED_DIR/graph"; exit 2; }

# make official-expected paths
mkdir -p "$MET_DIR"
ln -sfn "$SPACENET_DATA_ROOT" "$MET_DIR/spacenet"
test -f "$MET_DIR/spacenet/data_split.json" || { echo "[ERROR] missing data_split.json"; exit 3; }

# bind pred under spacenet_metrics for stable relative path
ln -sfn "$PRED_DIR" "$MET_DIR/_pred"

# logs dir
EVAL_DIR="$PRED_DIR/eval/topo"
mkdir -p "$EVAL_DIR"

echo "[TOPO] pred=$PRED_DIR"
echo "[TOPO] writing logs to $EVAL_DIR"

# run per-tile topo (official)
cd "$TOPO_DIR"
python3 main.py -savedir "_pred" 2>&1 | tee "$EVAL_DIR/topo_main.log"

# summarize using robust parser (your stable “paper mouth”)
cd "$REPO"
python3 tools/summarize_spacenet_topo_from_txt.py "$PRED_DIR" \
  2>&1 | tee "$EVAL_DIR/topo_summary_from_txt.log"

echo "[TOPO] done."
echo "[TOPO] outputs:"
echo "  - $PRED_DIR/results/topo/*.txt"
echo "  - $EVAL_DIR/topo_main.log"
echo "  - $EVAL_DIR/topo_summary_from_txt.csv"
echo "  - $EVAL_DIR/topo_summary_from_txt.log"
