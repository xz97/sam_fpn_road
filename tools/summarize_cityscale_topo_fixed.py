import os, glob, re, csv, argparse
import numpy as np

def parse_one(path: str):
    """
    CityScale topo txt contains coordinate-like lines (40.xx, -70.xx). We must avoid them.
    We extract:
      - Avg Precesion <float>
      - Avg Recall <float>
      - precision=<float> overall-recall=<float>  (optional)
    """
    txt = open(path, "r", encoding="utf-8", errors="ignore").read()

    # NOTE: in files the spelling is often "Precesion"
    mp = re.findall(r"Avg\s+Precesion\s+([0-9]*\.[0-9]+)", txt)
    mr = re.findall(r"Avg\s+Recall\s+([0-9]*\.[0-9]+)", txt)
    avg_p = float(mp[-1]) if mp else float("nan")
    avg_r = float(mr[-1]) if mr else float("nan")

    m1 = re.search(r"precision=([0-9.]+)", txt)
    m2 = re.search(r"overall-recall=([0-9.]+)", txt)
    prec_line = float(m1.group(1)) if m1 else float("nan")
    overall_rec_line = float(m2.group(1)) if m2 else float("nan")

    return avg_p, avg_r, prec_line, overall_rec_line

def main(pred_dir: str):
    topo_dir = os.path.join(pred_dir, "results", "topo")
    files = sorted(glob.glob(os.path.join(topo_dir, "*.txt")))
    if not files:
        raise SystemExit(f"[ERR] no topo txt under: {topo_dir}")

    out_dir = os.path.join(pred_dir, "eval", "topo")
    os.makedirs(out_dir, exist_ok=True)

    out_csv = os.path.join(out_dir, "topo_summary_fixed.csv")
    rows = []
    bad = []

    for f in files:
        try:
            ap, ar, pl, orl = parse_one(f)
            rows.append((os.path.basename(f), ap, ar, pl, orl))
        except Exception:
            bad.append(os.path.basename(f))

    with open(out_csv, "w", newline="") as fp:
        w = csv.writer(fp)
        w.writerow(["file", "avg_precision", "avg_recall", "precision_line", "overall_recall_line"])
        w.writerows(rows)

    arr = np.array([[r[1], r[2], r[3], r[4]] for r in rows], dtype=float)
    mean = np.nanmean(arr, axis=0)
    std  = np.nanstd(arr, axis=0)

    # Print in a stable "paper mouth" format
    print(f"[OK] files={len(files)} parsed={len(rows)} bad={len(bad)}")
    print(f"[MEAN] avg_precision={mean[0]:.6f} avg_recall={mean[1]:.6f} precision_line={mean[2]:.6f} overall_recall_line={mean[3]:.6f}")
    print(f"[STD]  avg_precision={std[0]:.6f} avg_recall={std[1]:.6f} precision_line={std[2]:.6f} overall_recall_line={std[3]:.6f}")
    print(f"[OK] wrote: {out_csv}")
    if bad:
        print("[WARN] bad files (first 30):", bad[:30])

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("pred_dir")
    args = ap.parse_args()
    main(args.pred_dir)
