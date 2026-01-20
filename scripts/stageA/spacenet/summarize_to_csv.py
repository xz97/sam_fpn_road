import re
from pathlib import Path

def mean_apls(results_dir: Path) -> float:
    txts = sorted((results_dir / "results" / "apls").glob("*.txt"))
    vals = []
    for p in txts:
        s = p.read_text(errors="ignore").strip()
        # 文件一般是一行数字，或者末尾带 apls: x
        m = re.search(r"([0-9]*\.[0-9]+)", s)
        if m:
            vals.append(float(m.group(1)))
    if not vals:
        return float("nan")
    return sum(vals) / len(vals)

def last_topo_from_log(log_path: Path):
    if not log_path.exists():
        return (float("nan"), float("nan"), float("nan"))
    lines = log_path.read_text(errors="ignore").splitlines()
    last = None
    for l in lines:
        if "TOPO " in l and "Precision" in l and "Recall" in l:
            last = l
    if not last:
        return (float("nan"), float("nan"), float("nan"))
    m = re.search(r"TOPO\s+([0-9.]+)\s+Precision\s+([0-9.]+)\s+Recall\s+([0-9.]+)", last)
    if not m:
        return (float("nan"), float("nan"), float("nan"))
    return (float(m.group(1)), float(m.group(2)), float(m.group(3)))

def row(name, save_dir, topo_log):
    save_dir = Path(save_dir)
    apls = mean_apls(save_dir)
    topo, prec, rec = last_topo_from_log(Path(topo_log))
    return name, apls, topo, prec, rec

rows = []
rows.append(row("SpaceNet 8x8", "save/spacenet_toponet_8x8", "/mnt/data/outputs/20260116_topo_8x8.log"))
rows.append(row("SpaceNet 4x4", "save/spacenet_toponet_4x4", "/mnt/data/outputs/20260116_topo_4x4.log"))

print("| Setting | APLS | TOPO | Precision | Recall |")
print("|---|---:|---:|---:|---:|")
for name, apls, topo, prec, rec in rows:
    def f(x):
        return "nan" if x != x else f"{x:.6f}"
    print(f"| {name} | {f(apls)} | {f(topo)} | {f(prec)} | {f(rec)} |")

# 也输出 CSV，方便你直接贴到论文/Excel
out = Path("/mnt/data/outputs/spacenet_final_table.csv")
out.parent.mkdir(parents=True, exist_ok=True)
with out.open("w") as fw:
    fw.write("setting,apls,topo,precision,recall\n")
    for name, apls, topo, prec, rec in rows:
        fw.write(f"{name},{apls},{topo},{prec},{rec}\n")
print(f"\n[OK] CSV saved to: {out}")
