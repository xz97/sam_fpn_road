import argparse, glob, math, re
from pathlib import Path

def f1(p, r):
    return (2*p*r/(p+r)) if (p+r) > 0 else float("nan")

def read_text(p):
    return Path(p).read_text(errors="ignore").replace("\r", "\n").strip()

def is_bad(txt):
    return (not txt) or bool(re.search(r"\bnan\b", txt, flags=re.I))

# --- TOPO parsing ---
# Your topo txt has many lines; the LAST line contains 4 floats:
#   avg_precision avg_recall precision recall
# We only extract floats WITH decimal points from the LAST non-empty line.
float_pat = re.compile(r"[-+]?\d*\.\d+(?:[eE][-+]?\d+)?")

def parse_topo_file(p):
    txt = read_text(p)
    if is_bad(txt):
        return None
    lines = [l.strip() for l in txt.splitlines() if l.strip()]
    if not lines:
        return None
    last = lines[-1]
    floats = [float(x) for x in float_pat.findall(last)]
    if len(floats) < 2:
        return None
    # If it contains 4 floats, take first two as AvgP/AvgR (matches your sample).
    avg_p, avg_r = floats[0], floats[1]
    if any(math.isnan(v) for v in [avg_p, avg_r]):
        return None
    topo = f1(avg_p, avg_r)
    if math.isnan(topo):
        return None
    return topo, avg_p, avg_r

# --- APLS parsing ---
# Your apls txt is usually either:
#   "NaN NaN NaN"
#   or "x y apls"
# We take the LAST numeric token.
num_pat = re.compile(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?")

def parse_apls_file(p):
    txt = read_text(p)
    if is_bad(txt):
        return None
    nums = [x for x in num_pat.findall(txt)]
    if not nums:
        return None
    v = float(nums[-1])
    return None if math.isnan(v) else v

def mean(vals):
    return (sum(vals)/len(vals)) if vals else float("nan")

def summarize(setting_name, base_dir):
    topo_files = glob.glob(str(Path(base_dir) / "results" / "topo" / "*.txt"))
    apls_files = glob.glob(str(Path(base_dir) / "results" / "apls" / "*.txt"))

    topo_vals, ps, rs = [], [], []
    for fp in topo_files:
        out = parse_topo_file(fp)
        if out is None:
            continue
        t, p, r = out
        topo_vals.append(t); ps.append(p); rs.append(r)

    apls_vals = []
    for fp in apls_files:
        v = parse_apls_file(fp)
        if v is None:
            continue
        apls_vals.append(v)

    return {
        "Setting": setting_name,
        "APLS": mean(apls_vals),
        "TOPO": mean(topo_vals),
        "Precision": mean(ps),
        "Recall": mean(rs),
        "topo_txt_total": len(topo_files),
        "topo_txt_used": len(topo_vals),
        "apls_txt_total": len(apls_files),
        "apls_txt_used": len(apls_vals),
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--metrics_root", required=True)
    ap.add_argument("--out_csv", required=True)
    args = ap.parse_args()

    root = Path(args.metrics_root)

    rows = [
        summarize("SpaceNet 8x8", root / "spacenet_toponet_8x8"),
        summarize("SpaceNet 4x4", root / "spacenet_toponet_4x4"),
    ]

    out = Path(args.out_csv)
    out.parent.mkdir(parents=True, exist_ok=True)

    header = ["Setting","APLS","TOPO","Precision","Recall",
              "topo_txt_total","topo_txt_used","apls_txt_total","apls_txt_used"]
    lines = [",".join(header)]
    for r in rows:
        lines.append(",".join(str(r[k]) for k in header))
    out.write_text("\n".join(lines) + "\n")

    print("Wrote:", out)
    for r in rows:
        print(r)

if __name__ == "__main__":
    main()
