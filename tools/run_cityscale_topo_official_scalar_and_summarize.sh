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

# bind dataset (optional; keep for official scripts that expect it)
mkdir -p "$MET_DIR"
ln -sfn "$CITYSCALE_DATA_ROOT" "$MET_DIR/cityscale" || true

# bind pred under cityscale_metrics for stable relative path
ln -sfn "$PRED_DIR" "$MET_DIR/_pred"

EVAL_DIR="$PRED_DIR/eval/topo"
mkdir -p "$EVAL_DIR"

echo "[TOPO] pred=$PRED_DIR"
echo "[TOPO] writing logs to $EVAL_DIR"
echo "[TOPO] metrics_dir=$MET_DIR"

# --- Patch main.py to append METRIC line (idempotent) ---
PATCH_SENTINEL="METRIC P="
MAIN_PY="$TOPO_DIR/main.py"

if ! grep -q "$PATCH_SENTINEL" "$MAIN_PY"; then
  echo "[PATCH] main.py: append METRIC line after TOPOWithPairs"
  python3 - <<'PY'
import pathlib
p=pathlib.Path("cityscale_metrics/topo/main.py")
s=p.read_text(encoding="utf-8").splitlines()

out=[]
inserted=False
for line in s:
    out.append(line)
    if (not inserted) and "topoResult" in line and "TOPOWithPairs" in line:
        out.append("    # --- PATCH: emit scalar metrics in a stable format (once debug + every tile metric line) ---")
        out.append("    if not hasattr(args, '_topo_debug_done'):")
        out.append("        args._topo_debug_done = True")
        out.append("        print('[DEBUG] topoResult repr:', repr(topoResult)[:2000])")
        out.append("")
        out.append("    # try to extract scalar P/R/TOPO from common topoResult structures")
        out.append("    P=R=T=None")
        out.append("    try:")
        out.append("        if isinstance(topoResult, dict):")
        out.append("            for k in ['P','p','precision','Precision']:")
        out.append("                if k in topoResult: P=float(topoResult[k]); break")
        out.append("            for k in ['R','r','recall','Recall']:")
        out.append("                if k in topoResult: R=float(topoResult[k]); break")
        out.append("            for k in ['TOPO','topo','Topo','F','f1','score']:")
        out.append("                if k in topoResult: T=float(topoResult[k]); break")
        out.append("        if (P is None or R is None or T is None) and isinstance(topoResult, (list,tuple)) and len(topoResult)>=3:")
        out.append("            tail = topoResult[-3:]")
        out.append("            if all(isinstance(x,(int,float)) for x in tail):")
        out.append("                P,R,T = map(float, tail)")
        out.append("    except Exception as e:")
        out.append("        print('[WARN] cannot parse topoResult scalars:', e)")
        out.append("")
        out.append("    # append a clean metric line to the txt output for THIS tile")
        out.append("    try:")
        out.append("        with open(args.output, 'a') as _f:")
        out.append("            if P is not None and R is not None and T is not None:")
        out.append("                _f.write(f\"\\nMETRIC P={P:.6f} R={R:.6f} TOPO={T:.6f}\\n\")")
        out.append("            else:")
        out.append("                _f.write(\"\\nMETRIC P=nan R=nan TOPO=nan\\n\")")
        out.append("    except Exception as e:")
        out.append("        print('[WARN] cannot append METRIC line:', e)")
        inserted=True

if not inserted:
    raise SystemExit("ERROR: cannot find TOPOWithPairs call line to patch")
p.write_text("\n".join(out) + "\n", encoding="utf-8")
print("OK: patched cityscale_metrics/topo/main.py")
PY
fi

# clear old topo outputs for safety
rm -rf "$PRED_DIR/results/topo"
mkdir -p "$PRED_DIR/results/topo"

# run official topo main
cd "$TOPO_DIR"
python3 main.py -savedir "_pred" 2>&1 | tee "$EVAL_DIR/topo_main.log"

# summarize METRIC lines -> CSV + log
cd "$REPO"
export PRED_DIR_ABS="$PRED_DIR"
python3 - <<'PY'
import os, glob, re, csv, numpy as np
pred_dir = os.environ["PRED_DIR_ABS"]
pat = re.compile(r"METRIC\s+P=([0-9.]+|nan)\s+R=([0-9.]+|nan)\s+TOPO=([0-9.]+|nan)")
files = sorted(glob.glob(os.path.join(pred_dir,"results","topo","*.txt")))
vals=[]
bad=[]
rows=[]
for f in files:
    lines=open(f,"r",encoding="utf-8",errors="ignore").read().splitlines()
    m=None
    for ln in reversed(lines):
        m=pat.search(ln)
        if m: break
    if not m:
        bad.append(os.path.basename(f)); continue
    p,r,t=m.groups()
    if "nan" in (p,r,t):
        bad.append(os.path.basename(f)); continue
    p=float(p); r=float(r); t=float(t)
    vals.append((p,r,t))
    rows.append((os.path.basename(f), p, r, t))

out_dir=os.path.join(pred_dir,"eval","topo")
os.makedirs(out_dir, exist_ok=True)
out_csv=os.path.join(out_dir,"topo_scalar_summary.csv")
with open(out_csv,"w",newline="") as fp:
    w=csv.writer(fp)
    w.writerow(["file","P","R","TOPO"])
    w.writerows(rows)

arr=np.array(vals) if vals else np.zeros((0,3))
mean=arr.mean(axis=0) if len(vals) else (float("nan"),)*3
std =arr.std(axis=0)  if len(vals) else (float("nan"),)*3

out_log=os.path.join(out_dir,"topo_scalar_summary.log")
with open(out_log,"w") as fp:
    fp.write(f"[OK] files={len(files)} parsed={len(vals)} bad={len(bad)}\n")
    fp.write(f"[MEAN] P={mean[0]:.6f} R={mean[1]:.6f} TOPO={mean[2]:.6f}\n")
    fp.write(f"[STD]  P={std[0]:.6f} R={std[1]:.6f} TOPO={std[2]:.6f}\n")
    if bad:
        fp.write("[WARN] bad tiles (first 50): " + ",".join(bad[:50]) + "\n")
print(open(out_log).read().strip())
print(f"[OK] wrote: {out_csv}")
print(f"[OK] wrote: {out_log}")
PY

echo "[TOPO] done."
echo "[TOPO] outputs:"
echo "  - $PRED_DIR/results/topo/*.txt (now ends with METRIC P/R/TOPO)"
echo "  - $EVAL_DIR/topo_main.log"
echo "  - $EVAL_DIR/topo_scalar_summary.csv"
echo "  - $EVAL_DIR/topo_scalar_summary.log"
