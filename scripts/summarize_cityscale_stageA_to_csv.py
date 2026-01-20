import os, json, csv, argparse, re

def _get(d, *keys, default=None):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur

def _first(d, candidates, default=None):
    for k in candidates:
        if isinstance(d, dict) and k in d and d[k] is not None:
            return d[k]
    return default

def _read_infer_time_sec(save_dir):
    p = os.path.join(save_dir, "inference_time.txt")
    if not os.path.exists(p):
        return None
    s = open(p, "r", encoding="utf-8", errors="ignore").read()
    m = re.search(r"in\s+([0-9]*\.?[0-9]+)\s+seconds", s)
    return float(m.group(1)) if m else None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--save_dir", required=True, help="e.g., save/cityscale_toponet_8x8_best")
    ap.add_argument("--setting", default="CityScale 8x8", help="row name in csv")
    ap.add_argument("--out_csv", default="results/StageA_cityscale_train_infer.csv")
    ap.add_argument("--out_readme", default="results/README_StageA_CityScale.md")
    args = ap.parse_args()

    save_dir = args.save_dir.rstrip("/")
    summary_path = os.path.join(save_dir, "score", "summary_cityscale_stageA.json")
    if not os.path.exists(summary_path):
        raise FileNotFoundError(f"missing: {summary_path}")

    summary = json.load(open(summary_path, "r"))

    # 兼容不同版本 key 命名（尽量不让你再 KeyError）
    apls_mean = _first(summary, [
        "final_APLS_mean_over_valid",
        "final_APLS",
        "APLS",
        "apls_mean",
    ])

    topo_mean = _first(summary, [
        "mean_TOPO",
        "TOPO",
        "topo_mean",
        "mean_topo",
    ])

    prec_mean = _first(summary, [
        "mean_P",
        "Precision",
        "precision_mean",
        "mean_precision",
    ])

    rec_mean = _first(summary, [
        "mean_R",
        "Recall",
        "recall_mean",
        "mean_recall",
    ])

    apls_valid = _first(summary, ["apls_valid", "valid_apls", "APLS_valid"])
    apls_total = _first(summary, ["apls_total", "total_apls", "APLS_total"])
    topo_valid = _first(summary, ["topo_valid", "valid_topo", "TOPO_valid"])
    topo_total = _first(summary, ["topo_total", "total_topo", "TOPO_total"])

    bad_apls = _first(summary, ["apls_bad_tile_ids", "bad_tile_ids_apls", "bad_tiles_apls", "bad_tile_ids_APLS"], default=[])
    bad_topo = _first(summary, ["topo_bad_tile_ids", "bad_tile_ids_topo", "bad_tiles_topo", "bad_tile_ids_TOPO"], default=[])

    infer_sec = _read_infer_time_sec(save_dir)

    row = {
        "Setting": args.setting,
        "APLS": apls_mean,
        "TOPO": topo_mean,
        "Precision": prec_mean,
        "Recall": rec_mean,
        "inference_time_sec": infer_sec,
        "apls_txt_total": apls_total,
        "apls_txt_used": apls_valid,
        "topo_txt_total": topo_total,
        "topo_txt_used": topo_valid,
        "bad_tiles_apls": ",".join(map(str, bad_apls)) if isinstance(bad_apls, list) else str(bad_apls),
        "bad_tiles_topo": ",".join(map(str, bad_topo)) if isinstance(bad_topo, list) else str(bad_topo),
        "summary_json": summary_path,
    }

    os.makedirs(os.path.dirname(args.out_csv), exist_ok=True)
    write_header = not os.path.exists(args.out_csv)
    with open(args.out_csv, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(row.keys()))
        if write_header:
            w.writeheader()
        w.writerow(row)

    # README（固定模板，避免你每次手写）
    os.makedirs(os.path.dirname(args.out_readme), exist_ok=True)
    with open(args.out_readme, "w", encoding="utf-8") as f:
        f.write(
f"""# StageA - CityScale (Train + Infer + Metrics)

## What is included
- StageA training: checkpointing every epoch, logs under RUN_DIR.
- Inference outputs: graph/mask/viz saved under save_dir.
- Metrics:
  - APLS: computed via cityscale_metrics/apls (Go), results/*.txt under {save_dir}/results/apls/
  - TOPO: computed via cityscale_metrics/topo, results/*.txt under {save_dir}/results/topo/

## Key outputs
- Summary table:
  - {args.out_csv}

## Run notes
- Do not commit datasets, checkpoints, or large runtime outputs.
- Use python3 (not python).
- This repo writes a single-row CSV per run; rerun will append a new row.
"""
        )

    print("[OK] appended ->", args.out_csv)
    print("[OK] wrote    ->", args.out_readme)

if __name__ == "__main__":
    main()
