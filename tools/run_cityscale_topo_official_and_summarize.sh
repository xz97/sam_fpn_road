#!/usr/bin/env bash
set -euo pipefail

PRED_DIR_IN="${1:?Usage: $0 <PRED_DIR>}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOPO_DIR="$REPO/cityscale_metrics/topo"
MET_DIR="$REPO/cityscale_metrics"

# resolve pred dir to abs
if [[ "$PRED_DIR_IN" = /* ]]; then
  PRED_DIR="$PRED_DIR_IN"
else
  PRED_DIR="$(cd "$REPO/$PRED_DIR_IN" && pwd)"
fi

test -d "$PRED_DIR/graph" || { echo "[ERR] missing $PRED_DIR/graph"; exit 2; }
test -f "$TOPO_DIR/main.py" || { echo "[ERR] missing $TOPO_DIR/main.py"; exit 3; }

mkdir -p "$PRED_DIR/results/topo" "$PRED_DIR/eval/topo"

LOG="$PRED_DIR/eval/topo/topo_cityscale_official.log"
: > "$LOG"

echo "[TOPO official] PRED_DIR=$PRED_DIR" | tee -a "$LOG"
python3 -V | tee -a "$LOG"

# stable bind for official script relative paths
ln -sfn "$PRED_DIR" "$MET_DIR/_pred"

# clean outputs
rm -f "$PRED_DIR/results/topo"/*.txt "$PRED_DIR/results/topo"/*.p 2>/dev/null || true

# run official main.py
cd "$TOPO_DIR"
python3 main.py -savedir "_pred" 2>&1 | tee -a "$LOG"

# summarize using official meaning:
# Prec = precision=...
# Rec  = overall-recall=...
cd "$REPO"
PRED_DIR="$PRED_DIR" python3 - <<'PY' 2>&1 | tee -a "$LOG"
import os, glob, re, json, numpy as np

pred_dir = os.path.realpath(os.environ["PRED_DIR"])
topo_dir = os.path.join(pred_dir, "results", "topo")

paths = sorted(glob.glob(os.path.join(topo_dir, "*.txt")),
               key=lambda p:int(os.path.basename(p).split(".")[0]))
if not paths:
    raise SystemExit(f"[ERR] no topo txt found in {topo_dir}")

prec=[]; rec=[]; f1=[]
pat = re.compile(r"precision=([0-9eE\.\+\-]+)\s+overall-recall=([0-9eE\.\+\-]+)")

for path in paths:
    fn=os.path.basename(path)
    lines=open(path,"r",encoding="utf-8",errors="ignore").read().splitlines()
    hit=None
    for ln in reversed(lines):
        m=pat.search(ln.strip())
        if m:
            hit=m
            break
    if hit is None:
        raise SystemExit(f"[ERR] cannot find 'precision= overall-recall=' line in {fn}")
    p=float(hit.group(1)); r=float(hit.group(2))
    ff=0.0 if (p+r)==0 else (2*p*r/(p+r))
    prec.append(p); rec.append(r); f1.append(ff)

print(f"[MEAN] Prec={float(np.mean(prec)):.6f} Rec={float(np.mean(rec)):.6f} F1={float(np.mean(f1)):.6f}")
print(f"[STD]  Prec={float(np.std(prec)):.6f} Rec={float(np.std(rec)):.6f} F1={float(np.std(f1)):.6f}")

out_dir=os.path.join(pred_dir,"eval","topo")
os.makedirs(out_dir, exist_ok=True)
save_json=os.path.join(out_dir,"topo_prf_official.json")
with open(save_json,"w") as jf:
    json.dump({"mean":{"prec":float(np.mean(prec)),"rec_overall":float(np.mean(rec)),"f1":float(np.mean(f1))},
               "std":{"prec":float(np.std(prec)),"rec_overall":float(np.std(rec)),"f1":float(np.std(f1))},
               "per_tile":{"prec":prec,"rec_overall":rec,"f1":f1}}, jf, indent=2)
print("[SAVED]", save_json)
PY

echo "[OK] log=$LOG"
