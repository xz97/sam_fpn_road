#!/usr/bin/env python3
import os, sys, glob, csv, math, statistics

def parse_txt(path: str):
    """
    Expected formats vary; we parse numbers robustly.
    Typical per-tile topo txt contains 3 floats: topo precision recall (or similar).
    We'll collect: topo, precision, recall by reading all floats and taking first 3.
    """
    floats = []
    with open(path, "r") as f:
        for line in f:
            for tok in line.replace(",", " ").split():
                try:
                    floats.append(float(tok))
                except:
                    pass
    if len(floats) < 3:
        return None
    topo, prec, rec = floats[0], floats[1], floats[2]
    if not (math.isfinite(topo) and math.isfinite(prec) and math.isfinite(rec)):
        return None
    return topo, prec, rec

def mean_std(vals):
    if not vals:
        return float("nan"), float("nan")
    if len(vals) == 1:
        return vals[0], 0.0
    return statistics.mean(vals), statistics.pstdev(vals)

def main():
    if len(sys.argv) != 2:
        print("Usage: summarize_cityscale_topo_from_txt.py <PRED_DIR>")
        sys.exit(2)

    pred_dir = os.path.abspath(sys.argv[1])
    topo_dir = os.path.join(pred_dir, "results", "topo")
    if not os.path.isdir(topo_dir):
        print(f"[ERROR] missing topo_dir: {topo_dir}")
        sys.exit(3)

    txts = sorted(glob.glob(os.path.join(topo_dir, "*.txt")))
    rows = []
    bad = []
    for p in txts:
        tile = os.path.splitext(os.path.basename(p))[0]
        parsed = parse_txt(p)
        if parsed is None:
            bad.append(tile)
            continue
        topo, prec, rec = parsed
        rows.append((tile, topo, prec, rec))

    # stats
    topo_m, topo_s = mean_std([r[1] for r in rows])
    prec_m, prec_s = mean_std([r[2] for r in rows])
    rec_m,  rec_s  = mean_std([r[3] for r in rows])

    # outputs
    eval_dir = os.path.join(pred_dir, "eval", "topo")
    os.makedirs(eval_dir, exist_ok=True)

    csv_path = os.path.join(eval_dir, "topo_summary_from_txt.csv")
    with open(csv_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["tile", "topo", "precision", "recall"])
        for r in rows:
            w.writerow(list(r))

    bad_path = os.path.join(eval_dir, "topo_bad_tiles.txt")
    with open(bad_path, "w") as f:
        for t in bad:
            f.write(str(t) + "\n")

    print(f"files={len(txts)} good={len(rows)} bad={len(bad)}")
    print(f"TOPO_mean={topo_m} TOPO_std={topo_s}")
    print(f"Precision_mean={prec_m} Precision_std={prec_s}")
    print(f"Recall_mean={rec_m} Recall_std={rec_s}")
    print(f"[OK] wrote: {csv_path}")
    print(f"[OK] wrote: {bad_path}")

if __name__ == "__main__":
    main()
