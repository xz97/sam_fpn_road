import argparse, json, re, math
from pathlib import Path

def parse_eval_log(log_path: Path):
    txt = log_path.read_text(errors="ignore")
    # 只取最终一行：TOPO x Precision y Recall z
    m = re.findall(r"TOPO\s+([0-9.]+)\s+Precision\s+([0-9.]+)\s+Recall\s+([0-9.]+)", txt)
    if not m:
        return None
    topo, prec, rec = map(float, m[-1])
    return topo, prec, rec

def parse_apls_dir(apls_dir: Path):
    vals=[]
    for p in sorted(apls_dir.glob("*.txt")):
        s = p.read_text(errors="ignore").strip()
        if not s:
            continue
        # apls txt 通常最后一个数是 apls 或 3 列最后一列是 apls
        nums = re.findall(r"[-+]?\d*\.\d+|[-+]?\d+", s)
        if not nums:
            continue
        v=float(nums[-1])
        if math.isnan(v):
            continue
        vals.append(v)
    return vals

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--metrics_root", required=True)
    ap.add_argument("--eval_log", required=True)
    ap.add_argument("--out_csv", required=True)
    ap.add_argument("--out_json", required=True)
    ap.add_argument("--setting", default="CityScale 16x16 (stageA)")
    args = ap.parse_args()

    root = Path(args.metrics_root)
    topo_dir = root/"results"/"topo"
    apls_dir = root/"results"/"apls"
    graph_dir = root/"graph"
    log_path = Path(args.eval_log)

    topo_txt_total = len(list(topo_dir.glob("*.txt")))
    apls_txt_total = len(list(apls_dir.glob("*.txt")))
    graph_p_total  = len(list(graph_dir.glob("*.p")))

    topo_vals = parse_eval_log(log_path)
    if topo_vals is None:
        topo, prec, rec = float("nan"), float("nan"), float("nan")
    else:
        topo, prec, rec = topo_vals

    apls_vals = parse_apls_dir(apls_dir)
    apls_used = len(apls_vals)
    apls_mean = sum(apls_vals)/apls_used if apls_used>0 else float("nan")

    summary = {
        "Setting": args.setting,
        "DIR": str(root),
        "eval_log": str(log_path),
        "TOPO": topo,
        "Precision": prec,
        "Recall": rec,
        "APLS": apls_mean,
        "graph_p_total": graph_p_total,
        "topo_txt_total": topo_txt_total,
        "apls_txt_total": apls_txt_total,
        "apls_txt_used": apls_used,
    }

    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    out_csv = Path(args.out_csv)
    out_csv.write_text(
        "Setting,DIR,eval_log,APLS,TOPO,Precision,Recall,graph_p_total,topo_txt_total,apls_txt_total,apls_txt_used\n"
        f"{summary['Setting']},{summary['DIR']},{summary['eval_log']},{summary['APLS']},{summary['TOPO']},{summary['Precision']},{summary['Recall']},"
        f"{summary['graph_p_total']},{summary['topo_txt_total']},{summary['apls_txt_total']},{summary['apls_txt_used']}\n",
        encoding="utf-8"
    )

    print(summary)
    print(f"[WROTE] {out_csv}")
    print(f"[WROTE] {out_json}")

if __name__ == "__main__":
    main()
