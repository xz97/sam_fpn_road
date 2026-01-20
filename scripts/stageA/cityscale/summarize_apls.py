import argparse, glob, os, json, math

def parse_line(s: str):
    # expected: "apls_gt apls_prop apls_avg" (may be NaN)
    parts = s.strip().split()
    if len(parts) < 3:
        return None
    def to_float(x):
        try:
            # accept NaN/Inf tokens
            v = float(x)
            return v
        except Exception:
            return None
    a, b, c = to_float(parts[0]), to_float(parts[1]), to_float(parts[2])
    if a is None or b is None or c is None:
        return None
    return a, b, c

def is_finite(x: float) -> bool:
    return x is not None and math.isfinite(x)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--save_dir", required=True)
    args = ap.parse_args()

    save_dir = args.save_dir.rstrip("/")
    txt_dir = os.path.join(save_dir, "results", "apls")
    txts = sorted(glob.glob(os.path.join(txt_dir, "*.txt")))

    rows = {}
    bad = {}
    vals = []

    for p in txts:
        tid = os.path.splitext(os.path.basename(p))[0]
        try:
            line = open(p, "r").readline()
        except Exception as e:
            bad[tid] = f"read_error:{e}"
            continue

        parsed = parse_line(line)
        if parsed is None:
            bad[tid] = f"parse_error:{line.strip()}"
            continue

        apls_gt, apls_prop, apls_avg = parsed
        rows[tid] = {"apls_gt": apls_gt, "apls_prop": apls_prop, "apls": apls_avg}

        if is_finite(apls_avg):
            vals.append(apls_avg)
        else:
            bad[tid] = f"nan_or_inf:{line.strip()}"

    final = sum(vals) / len(vals) if len(vals) > 0 else float("nan")

    out = {
        "save_dir": save_dir,
        "txt_dir": txt_dir,
        "total_tiles": len(txts),
        "valid_tiles": len(vals),
        "bad_tiles": bad,                 # tile_id -> reason
        "bad_tile_ids": sorted(bad.keys()),
        "final_APLS_mean_over_valid": final,
        "per_tile": rows,
    }

    score_dir = os.path.join(save_dir, "score")
    os.makedirs(score_dir, exist_ok=True)
    out_path = os.path.join(score_dir, "apls_from_txt_v2.json")
    with open(out_path, "w") as f:
        json.dump(out, f, indent=2)
    print(f"[APLS] valid/total = {len(vals)} / {len(txts)}")
    print(f"[APLS] final_APLS_mean_over_valid = {final}")
    print(f"[APLS] bad_tile_ids = {sorted(bad.keys())}")
    print(f"[OK] wrote {out_path}")

if __name__ == "__main__":
    main()
