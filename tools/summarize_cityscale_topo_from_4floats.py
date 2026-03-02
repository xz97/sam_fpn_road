import os, glob, re, csv, argparse
import numpy as np

# match a line with exactly 4 floats separated by spaces
four = re.compile(r"^\s*([0-9]*\.[0-9]+)\s+([0-9]*\.[0-9]+)\s+([0-9]*\.[0-9]+)\s+([0-9]*\.[0-9]+)\s*$")

def parse_txt(path: str):
    lines = open(path, "r", encoding="utf-8", errors="ignore").read().splitlines()
    # search from bottom up for the first 4-float line
    for ln in reversed(lines):
        m = four.match(ln)
        if m:
            p, r, topo, overall = map(float, m.groups())
            return p, r, topo, overall
    return None

def main(pred_dir: str):
    topo_dir = os.path.join(pred_dir, "results", "topo")
    files = sorted(glob.glob(os.path.join(topo_dir, "*.txt")))
    if not files:
        raise SystemExit(f"[ERR] no topo txt under: {topo_dir}")

    out_dir = os.path.join(pred_dir, "eval", "topo")
    os.makedirs(out_dir, exist_ok=True)
    out_csv = os.path.join(out_dir, "topo_scalar_summary_from_4floats.csv")
    out_log = os.path.join(out_dir, "topo_scalar_summary_from_4floats.log")

    rows=[]
    bad=[]
    for f in files:
        res = parse_txt(f)
        if res is None:
            bad.append(os.path.basename(f))
            continue
        p, r, t, o = res
        rows.append((os.path.basename(f), p, r, t, o))

    arr = np.array([[r[1], r[2], r[3], r[4]] for r in rows], dtype=float)
    mean = np.mean(arr, axis=0) if len(rows) else [float("nan")]*4
    std  = np.std(arr, axis=0)  if len(rows) else [float("nan")]*4

    with open(out_csv, "w", newline="") as fp:
        w = csv.writer(fp)
        w.writerow(["file", "P", "R", "TOPO", "overall_recall"])
        w.writerows(rows)

    with open(out_log, "w") as fp:
        fp.write(f"[OK] files={len(files)} parsed={len(rows)} bad={len(bad)}\n")
        fp.write(f"[MEAN] P={mean[0]:.6f} R={mean[1]:.6f} TOPO={mean[2]:.6f} overall_recall={mean[3]:.6f}\n")
        fp.write(f"[STD]  P={std[0]:.6f} R={std[1]:.6f} TOPO={std[2]:.6f} overall_recall={std[3]:.6f}\n")
        if bad:
            fp.write("[WARN] bad files (first 50): " + ",".join(bad[:50]) + "\n")

    print(open(out_log).read().strip())
    print(f"[OK] wrote: {out_csv}")
    print(f"[OK] wrote: {out_log}")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("pred_dir")
    args = ap.parse_args()
    main(args.pred_dir)
