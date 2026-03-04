#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <PRED_DIR(abs or rel)> [--force]"
  exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRED_IN="$1"
FORCE="${2:-}"

# Resolve pred dir
if [[ "$PRED_IN" = /* ]]; then
  PRED_DIR="$PRED_IN"
else
  PRED_DIR="$(cd "$REPO/$PRED_IN" && pwd)"
fi

CONVERT_PY="$REPO/cityscale_metrics/apls/convert.py"
APLS_GO_DIR="$REPO/spacenet_metrics/apls"
SPLIT_JSON="$REPO/spacenet/data_split.json"
GT_DIR="$REPO/spacenet/RGB_1.0_meter"

OUT_DIR="$PRED_DIR/results/apls"
LOG_DIR="$PRED_DIR/eval/apls"
mkdir -p "$OUT_DIR" "$LOG_DIR"

echo "[APLS] PRED_DIR=$PRED_DIR"
echo "[APLS] OUT_DIR =$OUT_DIR"
echo "[APLS] LOG_DIR =$LOG_DIR"
echo "[APLS] CONVERT =$CONVERT_PY"
echo "[APLS] GO_DIR  =$APLS_GO_DIR"
echo "[APLS] FORCE   =$FORCE"

export GO111MODULE=on

mapfile -t TILES < <(jq -r '.test[]' "$SPLIT_JSON")
echo "[APLS] tiles=${#TILES[@]} (from $SPLIT_JSON)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ok=0; miss=0; bad=0; skip=0
for t in "${TILES[@]}"; do
  PFILE="$PRED_DIR/graph/${t}.p"
  GT_P="$GT_DIR/${t}__gt_graph.p"
  OUT_TXT="$OUT_DIR/${t}.txt"
  PER_LOG="$LOG_DIR/${t}.log"

  if [[ -s "$OUT_TXT" && "$FORCE" != "--force" ]]; then
    ((skip+=1))
    continue
  fi

  if [[ ! -f "$PFILE" ]]; then
    echo "[MISS] pred graph: $t ($PFILE)" | tee -a "$LOG_DIR/missing_pred.txt" >/dev/null
    ((miss+=1))
    continue
  fi
  if [[ ! -f "$GT_P" ]]; then
    echo "[MISS] gt graph:   $t ($GT_P)" | tee -a "$LOG_DIR/missing_gt.txt" >/dev/null
    ((miss+=1))
    continue
  fi

  echo "========================$t======================"

  python3 "$CONVERT_PY" "$GT_P"  "$WORK/gt.json"
  python3 "$CONVERT_PY" "$PFILE" "$WORK/prop.json"

  # Sanity check: ensure both jsons actually contain coordinate pairs
  python3 - "$t" "$WORK/gt.json" "$WORK/prop.json" <<'PY' 2> "$LOG_DIR/${t}.badjson.log" || {
import json, math, sys

tile = sys.argv[1]
gtp  = sys.argv[2]
prp  = sys.argv[3]

def is_num(x):
    return isinstance(x, (int, float)) and math.isfinite(float(x))

def count_xy(obj):
    c = 0
    def rec(o):
        nonlocal c
        if isinstance(o, dict):
            # dict with x/y
            if "x" in o and "y" in o and is_num(o["x"]) and is_num(o["y"]):
                c += 1
            # dict with lon/lat
            if "lon" in o and "lat" in o and is_num(o["lon"]) and is_num(o["lat"]):
                c += 1
            # dict with coord: [x,y]
            if "coord" in o and isinstance(o["coord"], list) and len(o["coord"]) >= 2 and is_num(o["coord"][0]) and is_num(o["coord"][1]):
                c += 1
            for v in o.values():
                rec(v)
        elif isinstance(o, list):
            # list pair [x,y]
            if len(o) == 2 and is_num(o[0]) and is_num(o[1]):
                c += 1
            else:
                for v in o:
                    rec(v)
    rec(obj)
    return c

gt = json.load(open(gtp, "r"))
pr = json.load(open(prp, "r"))

gtc = count_xy(gt)
prc = count_xy(pr)

if gtc == 0 or prc == 0:
    print(f"[BAD_JSON] tile={tile} gt_xy={gtc} prop_xy={prc}", file=sys.stderr)
    sys.exit(3)
print(f"[OK_JSON] tile={tile} gt_xy={gtc} prop_xy={prc}", file=sys.stderr)
PY
    echo "[BAD] json has no coords for tile=$t (see $LOG_DIR/${t}.badjson.log)"
    ((bad+=1))
    continue
  }

  # Run official go main.go
  ( cd "$APLS_GO_DIR" && go run main.go "$WORK/gt.json" "$WORK/prop.json" "$OUT_TXT" spacenet ) \
    2>&1 | tee "$PER_LOG"

  ((ok+=1))
done

echo "[APLS] per-tile done: ok=$ok skip=$skip miss=$miss bad=$bad"
echo "[APLS] txt_count=$(ls -1 "$OUT_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')"

# Summary
python3 "$REPO/spacenet_metrics/apls.py" --dir "$PRED_DIR" 2>&1 | tee "$LOG_DIR/apls_summary.log"
echo "[APLS] summary_log=$LOG_DIR/apls_summary.log"
