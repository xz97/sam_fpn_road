import argparse, json
from pathlib import Path

COLS = [
  "Stage","Dataset","Setting",
  "APLS","TOPO","Precision","Recall",
  "tiles_total","apls_used","topo_used",
  "metrics_root","eval_log"
]

def load_json(p: Path):
    return json.loads(p.read_text())

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spacenet_json", required=True)
    ap.add_argument("--cityscale_json", required=True)
    ap.add_argument("--out_csv", required=True)
    args = ap.parse_args()

    s = load_json(Path(args.spacenet_json))
    c = load_json(Path(args.cityscale_json))

    # SpaceNet：你那份 json 字段一般包含：DIR/APLS/TOPO/Precision/Recall/topo_txt_total/topo_txt_used/apls_txt_total/apls_txt_used
    spacenet_row = {
        "Stage":"A",
        "Dataset":"spacenet",
        "Setting": s.get("Setting","SpaceNet 16x16 (stageA)"),
        "APLS": s.get("APLS",""),
        "TOPO": s.get("TOPO",""),
        "Precision": s.get("Precision",""),
        "Recall": s.get("Recall",""),
        "tiles_total": s.get("apls_txt_total", s.get("topo_txt_total","")),
        "apls_used": s.get("apls_txt_used",""),
        "topo_used": s.get("topo_txt_used",""),
        "metrics_root": s.get("DIR", s.get("metrics_root","")),
        "eval_log": s.get("eval_log",""),
    }

    # CityScale：你刚才的 json 字段包含：DIR/eval_log/APLS/TOPO/Precision/Recall/graph_p_total/topo_txt_total/apls_txt_total/apls_txt_used
    cityscale_row = {
        "Stage":"A",
        "Dataset":"cityscale",
        "Setting": c.get("Setting","CityScale 16x16 (stageA)"),
        "APLS": c.get("APLS",""),
        "TOPO": c.get("TOPO",""),
        "Precision": c.get("Precision",""),
        "Recall": c.get("Recall",""),
        "tiles_total": c.get("graph_p_total", c.get("topo_txt_total","")),
        "apls_used": c.get("apls_txt_used", c.get("apls_txt_total","")),
        "topo_used": c.get("topo_txt_total",""),
        "metrics_root": c.get("DIR", c.get("metrics_root","")),
        "eval_log": c.get("eval_log",""),
    }

    out = Path(args.out_csv)
    out.parent.mkdir(parents=True, exist_ok=True)

    lines = [",".join(COLS)]
    for row in [spacenet_row, cityscale_row]:
        lines.append(",".join(str(row.get(k,"")) for k in COLS))
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[WROTE] {out}")

if __name__ == "__main__":
    main()
