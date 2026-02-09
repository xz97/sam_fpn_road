import re, sys, math
from pathlib import Path
import numpy as np

# Usage:
#   python3 tools/summarize_spacenet_topo_from_txt.py <PRED_DIR>

FLOAT = r"[-+]?(?:\d+\.\d+|\d+)(?:[eE][-+]?\d+)?"

# Your tile txt clearly contains:
#  - last numeric line with 4 floats: p  avg?  topo  overall-recall
#  - final line: precision=... overall-recall=...
PAT_LAST4 = re.compile(rf"^\s*({FLOAT})\s+({FLOAT})\s+({FLOAT})\s+({FLOAT})\s*$")
PAT_P_R = re.compile(rf"precision\s*=\s*({FLOAT}).*overall-recall\s*=\s*({FLOAT})", re.I)

def finite(*xs):
    return all(math.isfinite(float(x)) for x in xs)

def extract_metrics(txt: str):
    lines = [l.strip() for l in txt.splitlines() if l.strip()]
    if not lines:
        return None

    # 1) Prefer explicit "precision= ... overall-recall= ..."
    p = r = None
    for l in reversed(lines[-50:]):
        m = PAT_P_R.search(l)
        if m:
            p, r = map(float, m.groups())
            if finite(p, r):
                break

    # 2) Find the last "4 floats" line (often right above the precision= line)
    topo = None
    for l in reversed(lines[-120:]):
        m = PAT_LAST4.match(l)
        if m:
            a, b, c, d = map(float, m.groups())
            if finite(a, b, c, d):
                # Based on your sample:
                #   a = precision (matches precision=...)
                #   d = overall-recall (matches overall-recall=...)
                #   c behaves like TOPO (the value you want)
                topo = c
                # If p/r missing, take from this line
                if p is None: p = a
                if r is None: r = d
                break

    if p is None or r is None or topo is None:
        return None
    return topo, p, r

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/summarize_spacenet_topo_from_txt.py <PRED_DIR>")
        sys.exit(2)

    pred = Path(sys.argv[1]).expanduser().resolve()
    topo_dir = pred / "results" / "topo"
    files = sorted(topo_dir.glob("*.txt"))
    if not files:
        raise SystemExit(f"[ERROR] no topo txt found under {topo_dir}")

    good = []
    bad = []
    for f in files:
        try:
            txt = f.read_text(errors="ignore")
        except Exception as e:
            bad.append((f.name, f"read_error:{e}"))
            continue
        if f.stat().st_size == 0:
            bad.append((f.name, "empty"))
            continue
        val = extract_metrics(txt)
        if val is None:
            tail = "\n".join(txt.strip().splitlines()[-3:])[:200] if txt.strip() else "blank"
            bad.append((f.name, f"no_match tail='{tail}'"))
        else:
            topo, p, r = val
            good.append((f.stem, topo, p, r))

    print(f"files={len(files)} good={len(good)} bad={len(bad)}")
    out_dir = pred / "eval" / "topo"
    out_dir.mkdir(parents=True, exist_ok=True)

    if good:
        arr = np.array([[x[1], x[2], x[3]] for x in good], dtype=float)
        topo_m, p_m, r_m = arr.mean(axis=0)
        topo_s, p_s, r_s = arr.std(axis=0)
        print(f"TOPO_mean={topo_m:.9f} TOPO_std={topo_s:.9f}")
        print(f"Precision_mean={p_m:.9f} Precision_std={p_s:.9f}")
        print(f"Recall_mean={r_m:.9f} Recall_std={r_s:.9f}")
    else:
        print("[ERROR] No valid entries parsed. Check txt format or patterns.")

    out_csv = out_dir / "topo_summary_from_txt.csv"
    with out_csv.open("w") as w:
        w.write("tile,topo,precision,recall\n")
        for tile, topo, p, r in good:
            w.write(f"{tile},{topo:.9f},{p:.9f},{r:.9f}\n")

    out_bad = out_dir / "topo_bad_tiles.txt"
    with out_bad.open("w") as w:
        for name, reason in bad:
            w.write(f"{name}\t{reason}\n")

    print(f"[OK] wrote: {out_csv}")
    print(f"[OK] wrote: {out_bad}")

if __name__ == "__main__":
    main()
