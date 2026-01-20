import argparse, glob, os, json, re
import numpy as np

PAT_P = re.compile(r"Avg\s+Prec(?:e)?sion\s+([0-9eE\.\+\-]+)", re.IGNORECASE)   # Precesion / Precision
PAT_R = re.compile(r"Avg\s+Recall\s+([0-9eE\.\+\-]+)", re.IGNORECASE)

def parse_file(path: str):
    # 从后往前找：最后一次出现 Avg Precision/Precesion & Avg Recall 的行
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = [ln.strip() for ln in f.readlines() if ln.strip()]

    for ln in reversed(lines):
        mP = PAT_P.search(ln)
        mR = PAT_R.search(ln)
        if mP and mR:
            P = float(mP.group(1))
            R = float(mR.group(1))
            if np.isfinite(P) and np.isfinite(R):
                topo = 0.0 if (P + R) == 0 else (2 * P * R) / (P + R)  # F1
                return P, R, topo, ln

    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--save_dir", required=True)
    ap.add_argument("--in_subdir", default="results/topo")
    args = ap.parse_args()

    base = os.path.abspath(args.save_dir)
    in_dir = os.path.join(base, args.in_subdir)
    txts = sorted(glob.glob(os.path.join(in_dir, "*.txt")))

    Ps, Rs, Ts = [], [], []
    bad = []
    per_tile = {}

    for p in txts:
        tid = os.path.splitext(os.path.basename(p))[0]
        out = parse_file(p)
        if out is None:
            bad.append(tid)
            continue
        P, R, T, last_ln = out
        Ps.append(P); Rs.append(R); Ts.append(T)
        per_tile[tid] = {"P": P, "R": R, "TOPO": T, "picked_line": last_ln}

    Ps = np.array(Ps, dtype=float)
    Rs = np.array(Rs, dtype=float)
    Ts = np.array(Ts, dtype=float)

    result = {
        "valid": int(len(Ps)),
        "total": int(len(txts)),
        "TOPO_mean_over_valid": float(np.mean(Ts)) if len(Ts) else float("nan"),
        "Precision_mean_over_valid": float(np.mean(Ps)) if len(Ps) else float("nan"),
        "Recall_mean_over_valid": float(np.mean(Rs)) if len(Rs) else float("nan"),
        "bad_tile_ids": bad,
        "input_dir": in_dir,
        "per_tile": per_tile,
    }

    out_path = os.path.join(base, "score", "topo_from_txt_v3.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[TOPO] valid/total = {result['valid']} / {result['total']}")
    print(f"[TOPO] mean TOPO = {result['TOPO_mean_over_valid']}")
    print(f"[TOPO] mean P    = {result['Precision_mean_over_valid']}")
    print(f"[TOPO] mean R    = {result['Recall_mean_over_valid']}")
    print(f"[TOPO] bad_tile_ids = {bad}")
    print(f"[OK] wrote {out_path}")

if __name__ == "__main__":
    main()
