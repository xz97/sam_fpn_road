#!/usr/bin/env bash
set -euo pipefail

# =========================
# User-editable
# =========================
RUN_NAME="${RUN_NAME:-20260302_perfA_spacenet_official_init_main}"
CFG="${CFG:-config/toponet_vitb_256_spacenet.yaml}"
OFFICIAL_INIT="${OFFICIAL_INIT:-/mnt/data/ckpts/samroad_official/spacenet_vitb_256_e10.ckpt}"
RUN_DIR="${RUN_DIR:-/mnt/data/outputs/$RUN_NAME}"

# =========================
# Derived
# =========================
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S3_BASE="s3://samroad-20260115-5976/runs/$RUN_NAME"
OUT_NAME="spacenet_toponet_16x16_${RUN_NAME}_infer"

echo "==== PERF-A SpaceNet (official init, main pipeline) ===="
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

# dataset symlink required (dataset.py uses ./spacenet/data_split.json)
if [ ! -e "$REPO/spacenet" ]; then
  echo "[INFO] creating symlink: $REPO/spacenet -> /mnt/data/datasets/spacenet"
  ln -s /mnt/data/datasets/spacenet "$REPO/spacenet"
fi
test -f "$REPO/spacenet/data_split.json" || { echo "[ERR] missing spacenet/data_split.json"; exit 3; }

# pythonpath for segment-anything-road layout (your environment)
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
if [ -z "$CKPT" ]; then
  CKPT="$RUN_DIR/checkpoints/last.ckpt"
fi
test -f "$CKPT" || { echo "[ERR] no checkpoint found in $RUN_DIR/checkpoints"; exit 4; }
echo "CKPT=$CKPT"
ls -lh "$CKPT"
echo

# =========================
# 3) INFER (OUT_NAME is a pure name)
# =========================
echo "==== 3) INFER ===="
# keep a stable inference log outside pred dir (pred dir not known yet)
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
#   Find "<something>/<OUT_NAME>/graph" under repo
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
if [ "$GRAPH_COUNT" -lt 50 ]; then
  echo "[WARN] graph_count is low (<50). Eval will be meaningless."
  echo "[WARN] check $PRED_DIR/eval/infer_stdout.log"
fi
echo

# =========================
# 5) EVAL (wrapper scripts)
# =========================
echo "==== 5) EVAL APLS ===="
bash "$REPO/tools/run_spacenet_apls_official_main_go.sh" "$PRED_DIR" \
  2>&1 | tee "$PRED_DIR/eval/apls_stdout.log"
echo

echo "==== 5) EVAL TOPO ===="
bash "$REPO/tools/run_spacenet_topo_official_and_summarize.sh" "$PRED_DIR" \
  2>&1 | tee "$PRED_DIR/eval/topo_stdout.log"
echo

# =========================
# 6) FINAL SUMMARY
# =========================
echo "==== 6) FINAL SUMMARY ===="
mkdir -p "$PRED_DIR/eval/final"
cat > "$PRED_DIR/eval/final/FINAL_SUMMARY.txt" <<EOF
RUN=$RUN_NAME
CFG=$CFG
OFFICIAL_INIT=$OFFICIAL_INIT
RUN_DIR=$RUN_DIR
PRED_DIR=$PRED_DIR
TIME_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
graph_count=$GRAPH_COUNT

=== SpaceNet APLS (official Go) ===
$(tail -n 80 "$PRED_DIR/eval/apls/apls_summary.log" 2>/dev/null)

=== SpaceNet TOPO (official summarize) ===
$(tail -n 120 "$PRED_DIR/eval/topo/topo_summary_from_txt.log" 2>/dev/null)
EOF

tail -n 120 "$PRED_DIR/eval/final/FINAL_SUMMARY.txt"
echo

# =========================
# 7) ARCHIVE TO S3
# =========================
echo "==== 7) S3 ARCHIVE ===="
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
