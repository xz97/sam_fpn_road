# SpaceNet StageA Summary

| Setting | APLS | TOPO | Precision | Recall |
|---|---:|---:|---:|---:|
| SpaceNet 8x8 | 0.662451 | 0.000000 | 39.173818 | -67.837942 |
| SpaceNet 4x4 | 0.657323 | 0.000000 | 39.603127 | -68.581367 |

## Notes
- APLS is averaged over per-tile txt files in `results/apls/` (NaNs excluded).
- TOPO/Precision/Recall are averaged over per-tile txt files in `results/topo/` (NaNs excluded).
- `*_valid/total` columns in the CSV help diagnose missing/degenerate tiles.
