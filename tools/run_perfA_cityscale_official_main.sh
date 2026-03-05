#!/usr/bin/env bash
set -euo pipefail

# =========================
# User-editable
# =========================
RUN_NAME="${RUN_NAME:-20260303_perfA_cityscale_official_init_main}"
CFG="${CFG:-config/toponet_vitb_512_cityscale.yaml}"
OFFICIAL_INIT="${OFFICIAL_INIT:-/mnt/data/ckpts/samroad_official/cityscale_vitb_512_e10.ckpt}"
RUN_DIR="${RUN_DIR:-/mnt/data/outputs/$RUN_NAME}"

# =========================
# Derived
# =========================
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S3_BASE="s3://samroad-20260115-5976/runs/$RUN_NAME"
OUT_NAME="cityscale_toponet_16x16_${RUN_NAME}_infer"

echo "==== PERF-A CityScale (official init, main pipeline) ===="
echo "REPO=$REPO"
echo "RUN_NAME=$RUN_NAME"
echo "CFG=$CFG"
echo "OFFICIAL_INIT=$OFFICIAL_INIT"
echo "RUN_DIR=$RUN_DIR"
echo "OUT_NAME=$OUT_NAME"
echo "S3_BASE=$S3_BASE"
echo

# =========================
# Checks
# =========================
test -f "$REPO/$CFG" || { echo "[ERR] missing CFG: $REPO/$CFG"; exit 2; }
test -f "$OFFICIAL_INIT" || { echo "[ERR] missing OFFICIAL_INIT: $OFFICIAL_INIT"; exit 2; }

# dataset symlink required (inferencer/dataset uses ./cityscale/20cities/...)
if [ ! -e "$REPO/cityscale" ]; then
  echo "[INFO] creating symlink: $REPO/cityscale -> /mnt/data/datasets/cityscale"
  ln -s /mnt/data/datasets/cityscale "$REPO/cityscale"
fi
test -f "$REPO/cityscale/20cities/region_8_sat.png" || { echo "[ERR] missing cityscale data under $REPO/cityscale"; exit 3; }

# your environment import layout
export PYTHONPATH="$REPO/segment-anything-road:$REPO:${PYTHONPATH:-}"

mkdir -p "$RUN_DIR"

# =========================
# 1) TRAIN (weight-only init)
# =========================
echo "==== 1) TRAIN ===="
python3 "$REPO/scripts/train_stageA.py" \
  --config "$CFG" \
  --run_dir "$RUN_DIR" \
  --init_ckpt "$OFFICIAL_INIT" \
  --precision 16 \
  --log_every_n_steps 50 \
  --every_n_train_steps 500 \
  2>&1 | tee "$RUN_DIR/train_stdout.log"
echo

# =========================
# 2) PICK CKPT
# =========================
echo "==== 2) PICK CKPT ===="
CKPT="$(ls -1t "$RUN_DIR/checkpoints"/best-*.ckpt 2>/dev/null | head -n 1 || true)"
if [ -z "$CKPT" ]; then CKPT="$RUN_DIR/checkpoints/last.ckpt"; fi
test -f "$CKPT" || { echo "[ERR] no checkpoint found in $RUN_DIR/checkpoints"; exit 4; }
echo "CKPT=$CKPT"
ls -lh "$CKPT"
echo

# =========================
# 3) INFER (OUT_NAME is a pure name)
# =========================
echo "==== 3) INFER ===="
INFER_LOG="/mnt/data/outputs/${RUN_NAME}_infer_stdout.log"
python3 "$REPO/inferencer.py" \
  --config "$CFG" \
  --checkpoint "$CKPT" \
  --device cuda \
  --output_dir "$OUT_NAME" \
  2>&1 | tee "$INFER_LOG"
echo

# =========================
# 4) RESOLVE REAL PRED_DIR (NO GUESSING)
# =========================
echo "==== 4) RESOLVE PRED_DIR ===="
cd "$REPO"
GDIR="$(find . -maxdepth 12 -type d -name graph -path "*${OUT_NAME}*/graph" 2>/dev/null | head -n 1 || true)"
if [ -z "$GDIR" ]; then
  echo "[ERR] cannot find graph dir for OUT_NAME=$OUT_NAME"
  echo "[HINT] list some graph dirs:"
  find . -maxdepth 10 -type d -name graph | head -n 50
  exit 5
fi
PRED_DIR="$(cd "$(dirname "$GDIR")" && pwd)"
echo "GDIR=$GDIR"
echo "PRED_DIR=$PRED_DIR"

mkdir -p "$PRED_DIR/eval"
cp -f "$INFER_LOG" "$PRED_DIR/eval/infer_stdout.log" || true

GRAPH_COUNT="$(ls -1 "$PRED_DIR/graph"/*.p 2>/dev/null | wc -l || true)"
echo "graph_count=$GRAPH_COUNT"
echo

# =========================
# 5) EVAL APLS (official Go wrapper)
# =========================
echo "==== 5) EVAL APLS (official Go) ===="
mkdir -p "$PRED_DIR/eval/apls"
bash "$REPO/tools/run_cityscale_apls_official_main_go.sh" "$PRED_DIR" \
  2>&1 | tee "$PRED_DIR/eval/apls/apls_stdout.log"
echo

# =========================
# 6) EVAL TOPO (official main.py + official summary: precision + overall-recall -> F1)
#    Use the robust CityScale runner you validated.
# =========================
echo "==== 6) EVAL TOPO (official P/overall-recall/F1) ===="
mkdir -p "$PRED_DIR/eval/topo"
# This script should exist in your repo; it runs cityscale_metrics/topo/main.py and then summarizes by parsing:
#   precision=... overall-recall=...
bash "$REPO/tools/run_cityscale_topo_official_and_summarize.sh" "$PRED_DIR" \
  2>&1 | tee "$PRED_DIR/eval/topo/topo_stdout.log"
echo

# =========================
# 7) FINAL SUMMARY
# =========================
echo "==== 7) FINAL SUMMARY ===="
mkdir -p "$PRED_DIR/eval/final"
cat > "$PRED_DIR/eval/final/FINAL_SUMMARY.txt" <<EOF
RUN=$RUN_NAME
CFG=$CFG
OFFICIAL_INIT=$OFFICIAL_INIT
RUN_DIR=$RUN_DIR
PRED_DIR=$PRED_DIR
TIME_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
graph_count=$GRAPH_COUNT

=== CityScale APLS (official Go) ===
$(tail -n 120 "$PRED_DIR/eval/apls/apls_summary.log" 2>/dev/null)

=== CityScale TOPO (official precision + overall-recall; F1 computed) ===
$(tail -n 120 "$PRED_DIR/eval/topo/topo_cityscale_official.log" 2>/dev/null)
EOF

tail -n 120 "$PRED_DIR/eval/final/FINAL_SUMMARY.txt"
echo

# =========================
# 8) ARCHIVE TO S3 (SAFE WHITELIST)
#   - sync RUN_DIR fully (training artifacts)
#   - sync infer outputs only: graph/results/eval (avoid syncing ./cityscale symlink)
# =========================
echo "==== 8) S3 ARCHIVE ===="
echo "[S3] sync train run_dir -> $S3_BASE/"
aws s3 sync "$RUN_DIR" "$S3_BASE/" --delete

echo "[S3] sync infer outputs (whitelist) -> $S3_BASE/save/$OUT_NAME/"
aws s3 sync "$PRED_DIR/graph" "$S3_BASE/save/$OUT_NAME/graph"
if [ -d "$PRED_DIR/results" ]; then
  aws s3 sync "$PRED_DIR/results" "$S3_BASE/save/$OUT_NAME/results"
fi
aws s3 sync "$PRED_DIR/eval" "$S3_BASE/save/$OUT_NAME/eval"

echo "[S3] upload FINAL_SUMMARY -> $S3_BASE/FINAL_SUMMARY.txt"
aws s3 cp "$PRED_DIR/eval/final/FINAL_SUMMARY.txt" "$S3_BASE/FINAL_SUMMARY.txt"

echo
echo "[OK] done."
echo "PRED_DIR=$PRED_DIR"
echo "FINAL_SUMMARY=$PRED_DIR/eval/final/FINAL_SUMMARY.txt"
echo "S3_BASE=$S3_BASE"
