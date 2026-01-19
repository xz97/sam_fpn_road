# StageA - SpaceNet (Train + Infer + Metrics)

## What is included
- StageA training: checkpointing every epoch, logs under RUN_DIR.
- Inference outputs: graph/mask/viz saved under metrics cache directory.
- Metrics:
  - APLS computed via Go code under spacenet_metrics/apls/
  - TOPO computed via spacenet_metrics/topo/

## Key outputs
- Summary table:
  - results/StageA_spacenet_train_infer.csv

## Repro pointers (high level)
1) Train StageA (SpaceNet)
- scripts/train_stageA.py + scripts/run_stageA_spacenet.sh

2) Inference (4x4 / 8x8 settings)
- inferencer.py with SpaceNet infer configs

3) Metrics
- spacenet_metrics/eval_schedule.bash (calls apls.bash + topo.bash)
- APLS: run Go from spacenet_metrics/apls directory (go run . ...)
- TOPO: python topo/main.py (wrapped by topo.bash)

## Notes
- Do not commit datasets, checkpoints, or large runtime outputs.
- Use python3 (not python).
