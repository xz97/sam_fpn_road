#!/usr/bin/env bash
set -euo pipefail

# Official CityScale APLS runner (main.go + convert.py)
# Usage:
#   bash tools/run_cityscale_apls_official_main_go.sh /abs/path/to/pred_dir
# pred_dir must contain: graph/*.p

PRED_ABS="${1:?Usage: $0 <PRED_ABS (infer dir contains graph/)>}"

REPO=~/repos/sam_road
APLS_DIR="$REPO/cityscale_metrics/apls"
CITYSCALE_20="/mnt/data/datasets/cityscale/20cities"

# Fixed CityScale test tiles (official split)
arr=(8 9 19 28 29 39 48 49 59 68 69 79 88 89 99 108 109 119 128 129 139 148 149 159 168 169 179)

# --- checks ---
test -d "$PRED_ABS"
test -d "$PRED_ABS/graph"
test -d "$APLS_DIR"
test -f "$APLS_DIR/main.go"
test -f "$APLS_DIR/convert.py"
test -d "$CITYSCALE_20"

OUT_DIR="$PRED_ABS/results/apls"
mkdir -p "$OUT_DIR"

LOG="$PRED_ABS/apls_cityscale_main_go.log"
: > "$LOG"

echo "[APLS main.go] PRED_ABS=$PRED_ABS" | tee -a "$LOG"
echo "[APLS main.go] OUT_DIR=$OUT_DIR"    | tee -a "$LOG"
echo "[APLS main.go] apls_dir=$APLS_DIR"  | tee -a "$LOG"
echo "[APLS main.go] go=$(go version)"    | tee -a "$LOG"

# IMPORTANT: run inside apls dir; -mod=mod makes deps consistent across stages
cd "$APLS_DIR"

# --- run per tile ---
for t in "${arr[@]}"; do
  PFILE="$PRED_ABS/graph/${t}.p"
  if [[ ! -f "$PFILE" ]]; then
    echo "[WARN] missing pred graph: $PFILE" | tee -a "$LOG"
    continue
  fi

  echo "========================${t}======================" | tee -a "$LOG"

  GT_P="$CITYSCALE_20/region_${t}_refine_gt_graph.p"
  GTJ="/tmp/gt_${t}.json"
  PRJ="/tmp/prop_${t}.json"
  OUTTXT="$OUT_DIR/${t}.txt"

  python3 convert.py "$GT_P"  "$GTJ"
  python3 convert.py "$PFILE" "$PRJ"

  # official invocation (README)
  go run -mod=mod main.go "$GTJ" "$PRJ" "$OUTTXT" 2>&1 | tee -a "$LOG"
done

# --- post-check: count txt ---
CNT="$(ls -1 "$OUT_DIR"/*.txt 2>/dev/null | wc -l || true)"
echo "[DONE] txt_count=$CNT saved to $OUT_DIR" | tee -a "$LOG"

# --- summarize APLS (mean/std) from txt last lines ---
python3 - << PY | tee -a "$LOG"
import glob, os, re, numpy as np, sys
out_dir = "$OUT_DIR"
files = glob.glob(os.path.join(out_dir, "*.txt"))
def tile_id(p): 
    return int(os.path.basename(p).split(".")[0])
files = sorted(files, key=tile_id)
vals=[]
rows=[]
for f in files:
    tile=tile_id(f)
    lines=open(f,"r").read().strip().splitlines()
    if not lines:
        raise SystemExit(f"empty txt: {f}")
    last=lines[-1]
    nums=[float(x) for x in re.findall(r"[-+]?\d*\.\d+|[-+]?\d+", last)]
    if len(nums) < 1:
        raise SystemExit(f"bad last line: {f} :: {last}")
    apls=nums[-1]
    vals.append(apls)
    rows.append((tile, apls, last))
a=np.array(vals, dtype=float)
print(f"[SUMMARY] tiles={len(a)} APLS_mean={a.mean():.9f} APLS_std={a.std():.9f}")
# print worst 5 tiles (lowest apls)
worst=sorted(rows, key=lambda x:x[1])[:5]
print("[SUMMARY] worst5 (tile, apls):", [(t, round(v,6)) for t,v,_ in worst])
PY

