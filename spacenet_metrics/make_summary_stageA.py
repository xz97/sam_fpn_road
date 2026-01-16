import argparse
import csv
import math
import re
from pathlib import Path

FLOAT_RE = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")

def parse_floats(text: str):
    return [float(x) for x in FLOAT_RE.findall(text)]

def read_apls_dir(results_apls_dir: Path):
    """
    Reads per-tile APLS outputs from *.txt.
    Expected line patterns:
      - "a b apls: c"
      - OR a single line with 3 floats
      - OR "NaN NaN NaN"
    Returns: (mean_apls, n_valid, n_total)
    """
    files = sorted(results_apls_dir.glob("*.txt"))
    vals = []
    for f in files:
        s = f.read_text(errors="ignore").strip()
        fs = parse_floats(s)
        # Heuristic: APLS is usually the last float on the line
        if len(fs) >= 1:
            v = fs[-1]
            if not (math.isnan(v) or math.isinf(v)):
                vals.append(v)

    n_total = len(files)
    n_valid = len(vals)
    mean = sum(vals) / n_valid if n_valid > 0 else float("nan")
    return mean, n_valid, n_total

def read_topo_dir(results_topo_dir: Path):
    """
    Reads per-tile topo outputs from *.txt.
    Common formats:
      - "TOPO x Precision y Recall z"
      - or "x y z"
    Returns: (mean_topo, mean_prec, mean_rec, n_valid, n_total)
    """
    files = sorted(results_topo_dir.glob("*.txt"))
    topo_vals, prec_vals, rec_vals = [], [], []
    for f in files:
        s = f.read_text(errors="ignore").strip()
        fs = parse_floats(s)

        # Heuristic:
        # If it contains >=3 floats, treat as (topo, precision, recall) in that order.
        # Else skip.
        if len(fs) >= 3:
            topo, prec, rec = fs[0], fs[1], fs[2]
            if not any(math.isnan(x) or math.isinf(x) for x in (topo, prec, rec)):
                topo_vals.append(topo)
                prec_vals.append(prec)
                rec_vals.append(rec)

    n_total = len(files)
    n_valid = len(topo_vals)
    if n_valid == 0:
        return float("nan"), float("nan"), float("nan"), 0, n_total

    return (
        sum(topo_vals) / n_valid,
        sum(prec_vals) / n_valid,
        sum(rec_vals) / n_valid,
        n_valid,
        n_total,
    )

def summarize_setting(setting_name: str, setting_dir: Path):
    # APLS
    apls_dir = setting_dir / "results" / "apls"
    if apls_dir.exists():
        apls, apls_valid, apls_total = read_apls_dir(apls_dir)
    else:
        apls, apls_valid, apls_total = float("nan"), 0, 0

    # TOPO
    topo_dir = setting_dir / "results" / "topo"
    if topo_dir.exists():
        topo, prec, rec, topo_valid, topo_total = read_topo_dir(topo_dir)
    else:
        topo, prec, rec, topo_valid, topo_total = float("nan"), float("nan"), float("nan"), 0, 0

    return {
        "Setting": setting_name,
        "APLS": apls,
        "TOPO": topo,
        "Precision": prec,
        "Recall": rec,
        "APLS_valid": apls_valid,
        "APLS_total": apls_total,
        "TOPO_valid": topo_valid,
        "TOPO_total": topo_total,
        "Path": str(setting_dir),
    }

def f6(x):
    if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))):
        return "nan"
    return f"{x:.6f}"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base_save_dir", default=str(Path.home() / "repos" / "sam_road" / "save"),
                    help="Directory containing spacenet_toponet_4x4 and spacenet_toponet_8x8")
    ap.add_argument("--out_prefix", default=str(Path.home() / "repos" / "sam_road" / "StageA_spacenet_train&infer"),
                    help="Output prefix (without extension). Use quotes if it contains &.")
    args = ap.parse_args()

    base = Path(args.base_save_dir).expanduser().resolve()
    out_prefix = Path(args.out_prefix).expanduser()

    rows = []
    for name in ["spacenet_toponet_8x8", "spacenet_toponet_4x4"]:
        p = base / name
        if not p.exists():
            raise FileNotFoundError(f"Missing directory: {p}")
        rows.append(summarize_setting(f"SpaceNet {name.split('_')[-1]}", p))

    # Write CSV
    csv_path = out_prefix.with_suffix(".csv")
    csv_cols = ["Setting", "APLS", "TOPO", "Precision", "Recall", "APLS_valid", "APLS_total", "TOPO_valid", "TOPO_total", "Path"]
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=csv_cols)
        w.writeheader()
        for r in rows:
            rr = r.copy()
            # keep raw floats in csv, but still fine
            w.writerow(rr)

    # Write Markdown
    md_path = out_prefix.with_suffix(".md")
    lines = []
    lines.append("# SpaceNet StageA Summary\n")
    lines.append("| Setting | APLS | TOPO | Precision | Recall |")
    lines.append("|---|---:|---:|---:|---:|")
    for r in rows:
        lines.append(
            f"| {r['Setting']} | {f6(r['APLS'])} | {f6(r['TOPO'])} | {f6(r['Precision'])} | {f6(r['Recall'])} |"
        )
    lines.append("\n## Notes")
    lines.append("- APLS is averaged over per-tile txt files in `results/apls/` (NaNs excluded).")
    lines.append("- TOPO/Precision/Recall are averaged over per-tile txt files in `results/topo/` (NaNs excluded).")
    lines.append("- `*_valid/total` columns in the CSV help diagnose missing/degenerate tiles.\n")
    md_path.write_text("\n".join(lines))

    print("[OK] Wrote:", csv_path)
    print("[OK] Wrote:", md_path)
    print("\nPreview:")
    for r in rows:
        print(
            f"{r['Setting']}: APLS={f6(r['APLS'])} (valid {r['APLS_valid']}/{r['APLS_total']}), "
            f"TOPO={f6(r['TOPO'])} P={f6(r['Precision'])} R={f6(r['Recall'])} "
            f"(valid {r['TOPO_valid']}/{r['TOPO_total']})"
        )

if __name__ == "__main__":
    main()
