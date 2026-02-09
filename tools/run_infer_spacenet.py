import os
import sys
from pathlib import Path

# Make repo root importable no matter where we run from
REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

import argparse
import yaml

# Now this works: inferencer.py is at repo root
import inferencer  # module
Inferencer = getattr(inferencer, "Inferencer", None)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--save_dir", required=True)
    args = ap.parse_args()

    if Inferencer is None:
        raise SystemExit("[ERROR] inferencer.py has no class named Inferencer")

    save_dir = Path(args.save_dir)
    save_dir.mkdir(parents=True, exist_ok=True)

    with open(args.config, "r") as f:
        cfg = yaml.safe_load(f)

    # record effective config for reproducibility
    (save_dir / "config.yaml").write_text(open(args.config, "r").read())

    # try common constructor signatures
    try:
        inf = Inferencer(cfg, ckpt_path=args.ckpt, save_dir=str(save_dir))
    except TypeError:
        try:
            inf = Inferencer(cfg, args.ckpt, str(save_dir))
        except TypeError as e:
            raise SystemExit(f"[ERROR] Inferencer init signature mismatch: {e}")

    # try common run methods
    for fn in ["infer", "run", "predict", "inference", "infer_all"]:
        if hasattr(inf, fn):
            getattr(inf, fn)()
            print(f"[OK] finished via Inferencer.{fn}()")
            return

    raise SystemExit("[ERROR] Inferencer has no infer/run/predict/inference/infer_all method.")

if __name__ == "__main__":
    main()
