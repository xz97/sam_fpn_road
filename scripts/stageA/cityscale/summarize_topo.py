import argparse, json, math, os, glob
import numpy as np

def _is_nan(x: float) -> bool:
    return (x is None) or (isinstance(x, float) and math.isnan(x))

def parse_line(line: str):
    """
    Expected tokens contain:
      ... Precesion <p> Recall <r> Avg Precesion <ap> Avg Recall <ar>
    Note: 'Precesion' is misspelled in original outputs; we follow that.
    """
    toks = line.strip().split()
    if not toks:
        return None
    def get_after(key):
        if key not in toks:
            return None
        i = toks.index(key)
        if i + 1 >= len(toks):
            return None
        try:
            return float(toks[i+1])
        except:
            return None

    p  = get_after("Precesion")
    r  = get_after("Recall")
    ap = get_after("Precesion")  # placeholder, overwritten below if exists
    ar = get_after("Recall")     # placeholder, overwritten below if exists

    # Try to read Avg Precesion / Avg Recall (optional)
    if "Avg" in toks:
        # safest: search exact sequences
        for j in range(len(toks)-2):
            if toks[j] == "Avg" and toks[j+1] == "Precesion":
                try: ap = float(toks[j+2])
                except: pass
            if toks[j] == "Avg" and toks[j+1] == "Recall":
                try: ar = float(toks[j+2])
                except: pass

    return p, r, ap, ar

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--save_dir", required=True)
    args = parser.parse_args()

    save_dir = os.path.abspath(args.save_dir)
    topo_dir = os.path.join(save_dir, "results", "topo")
    files = sorted(glob.glob(os.path.join(topo_dir, "*.txt")))

    if not files:
        raise FileNotFoundError(f"No topo txt found under: {topo_dir}")

    all_p, all_r = [], []
    tile_macro = []  # per-tile final Avg P/R (for reference)
    bad_tiles = []

    for fp in files:
        tile_id = os.path.splitext(os.path.basename(fp))[0]
        lines = [ln for ln in open(fp, "r", encoding="utf-8", errors="ignore").read().splitlines() if ln.strip()]

        tile_ps, tile_rs = [], []
        last_ap, last_ar = None, None

        for ln in lines:
            parsed = parse_line(ln)
            if parsed is None:
                continue
            p, r, ap, ar = parsed
            if p is not None and (not _is_nan(p)):
                tile_ps.append(p); all_p.append(p)
            if r is not None and (not _is_nan(r)):
                tile_rs.append(r); all_r.append(r)
            # keep last avg values if present
            if ap is not None and (not _is_nan(ap)):
                last_ap = ap
            if ar is not None and (not _is_nan(ar)):
                last_ar = ar

        if len(tile_ps) == 0 or len(tile_rs) == 0:
            bad_tiles.append(tile_id)
        else:
            # macro reference: per-tile final Avg P/R if available, else mean of per-line
            mac_p = last_ap if last_ap is not None else float(np.mean(tile_ps))
            mac_r = last_ar if last_ar is not None else float(np.mean(tile_rs))
            tile_macro.append((tile_id, mac_p, mac_r, len(lines)))

    # MICRO (paper-like): mean over all query lines across all tiles
    if len(all_p) == 0 or len(all_r) == 0:
        mean_p = float("nan"); mean_r = float("nan"); f1 = float("nan")
    else:
        mean_p = float(np.mean(all_p))
        mean_r = float(np.mean(all_r))
        f1 = (2*mean_p*mean_r/(mean_p+mean_r)) if (mean_p+mean_r) > 0 else float("nan")

    # Also compute MACRO over tiles (unweighted) for debugging
    if len(tile_macro) == 0:
        macro_p = float("nan"); macro_r = float("nan"); macro_f1 = float("nan")
    else:
        macro_p = float(np.mean([x[1] for x in tile_macro]))
        macro_r = float(np.mean([x[2] for x in tile_macro]))
        macro_f1 = (2*macro_p*macro_r/(macro_p+macro_r)) if (macro_p+macro_r) > 0 else float("nan")

    out = {
        "save_dir": save_dir,
        "topo_txt_dir": topo_dir,
        "num_tiles_total": len(files),
        "bad_tile_ids": bad_tiles,

        "micro_mean_precision": mean_p,
        "micro_mean_recall": mean_r,
        "micro_f1": f1,
        "micro_num_precision_samples": len(all_p),
        "micro_num_recall_samples": len(all_r),

        "macro_mean_precision_over_tiles": macro_p,
        "macro_mean_recall_over_tiles": macro_r,
        "macro_f1_over_tiles": macro_f1,
        "tiles_macro_detail": tile_macro[:50],  # avoid huge json
    }

    score_dir = os.path.join(save_dir, "score")
    os.makedirs(score_dir, exist_ok=True)
    out_path = os.path.join(score_dir, "topo_from_txt_v4_micro.json")
    with open(out_path, "w") as f:
        json.dump(out, f, indent=2)

    print(f"[TOPO] tiles total = {len(files)}")
    print(f"[TOPO] bad_tile_ids = {bad_tiles}")
    print(f"[TOPO] MICRO  P={mean_p:.6f} R={mean_r:.6f} F1={f1:.6f} (paper-like)")
    print(f"[TOPO] MACRO  P={macro_p:.6f} R={macro_r:.6f} F1={macro_f1:.6f} (debug)")
    print(f"[OK] wrote {out_path}")

if __name__ == "__main__":
    main()
