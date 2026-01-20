# StageA - CityScale (Train + Infer + Metrics)

## What is included
- StageA training: checkpointing every epoch, logs under RUN_DIR.
- Inference outputs: graph/mask/viz saved under save_dir.
- Metrics:
  - APLS: computed via cityscale_metrics/apls (Go), results/*.txt under save/cityscale_toponet_8x8_best/results/apls/
  - TOPO: computed via cityscale_metrics/topo, results/*.txt under save/cityscale_toponet_8x8_best/results/topo/

## Key outputs
- Summary table:
  - results/StageA_cityscale_train_infer.csv

## Run notes
- Do not commit datasets, checkpoints, or large runtime outputs.
- Use python3 (not python).
- This repo writes a single-row CSV per run; rerun will append a new row.
- Single source of truth： s3://samroad-20260115-5976/metrics_cache/cityscale_toponet_8x8_best/
