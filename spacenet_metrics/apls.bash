#!/usr/bin/env bash
set -euo pipefail

# Official-like SpaceNet APLS runner (safe paths, same convert.py + main.go).
# Usage:
#   bash spacenet_metrics/apls.bash <PRED_DIR_ABS_OR_REL>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PRED_IN="${1:?Usage: $0 <pred_dir_abs_or_rel>}"

# Resolve PRED_DIR absolute
if [[ "$PRED_IN" = /* ]]; then
  PRED_DIR="$PRED_IN"
else
  PRED_DIR="$(cd "$REPO_DIR/$PRED_IN" && pwd)"
fi

# Data roots (repo has symlink spacenet -> /mnt/data/datasets/spacenet)
SPACENET_DIR="$REPO_DIR/spacenet"
GT_ROOT="$SPACENET_DIR/RGB_1.0_meter"
SPLIT_JSON="$SPACENET_DIR/data_split.json"

test -f "$SPLIT_JSON" || { echo "[ERROR] missing $SPLIT_JSON"; exit 2; }
test -d "$PRED_DIR/graph" || { echo "[ERROR] missing $PRED_DIR/graph"; exit 3; }
test -d "$SCRIPT_DIR/apls" || { echo "[ERROR] missing $SCRIPT_DIR/apls"; exit 4; }

OUT_DIR="$PRED_DIR/results/apls"
mkdir -p "$OUT_DIR"

echo "[APLS] PRED_DIR=$PRED_DIR"
echo "[APLS] OUT_DIR=$OUT_DIR"
echo "[APLS] SPLIT_JSON=$SPLIT_JSON"
echo "[APLS] go=$(go version || true)"

# tiles list from split
mapfile -t arr < <(jq -r '.test[]' "$SPLIT_JSON")

# Work files in metrics dir (avoid polluting PRED_DIR root)
GT_JSON="$SCRIPT_DIR/gt.json"
PR_JSON="$SCRIPT_DIR/prop.json"

for tile in "${arr[@]}"; do
  PFILE="$PRED_DIR/graph/${tile}.p"
  GT_P="$GT_ROOT/${tile}__gt_graph.p"

  if [[ ! -f "$PFILE" ]]; then
    echo "[WARN] missing pred: $PFILE"
    continue
  fi
  if [[ ! -f "$GT_P" ]]; then
    echo "[WARN] missing gt: $GT_P"
    continue
  fi

  echo "========================${tile}======================"
  python3 "$SCRIPT_DIR/apls/convert.py" "$GT_P" "$GT_JSON"
  python3 "$SCRIPT_DIR/apls/convert.py" "$PFILE" "$PR_JSON"

  # official main.go
  ( cd "$SCRIPT_DIR/apls" && go run main.go "$GT_JSON" "$PR_JSON" "$OUT_DIR/${tile}.txt" spacenet )
done

# summary (keeps official behavior: reads $dir/results/apls/*.txt and aggregates)
python3 "$SCRIPT_DIR/apls.py" --dir "$PRED_DIR"
