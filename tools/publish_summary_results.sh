#!/usr/bin/env bash
set -euo pipefail

# ========== USER CONFIG ==========
BUCKET="samroad-20260115-5976"

# runs you showed in S3 (exact names)
RUNS=(
  "20260122_stageA_spacenet_16x16_stageA"
  "20260123_stageA_cityscale_16x16_stageA"
  "20260124_stageB_cityscale_cldice"
  "20260124_stageB_spacenet_cldice_v1"
)

# Where to write local summary artifacts
OUT_DIR="/mnt/data/results_final"

# Final numbers (from your table)
# NOTE: change only here if you update metrics later.
STAGEA_SPACENET_APLS="0.6860703068181818"
STAGEA_SPACENET_TOPO="0.755687100230051"
STAGEA_SPACENET_P="0.8285320844191961"
STAGEA_SPACENET_R="0.7010625166936558"

STAGEA_CITYSCALE_APLS="0.5886081111111111"
STAGEA_CITYSCALE_TOPO="0.7683627368283057"
STAGEA_CITYSCALE_P="0.8808322411525299"
STAGEA_CITYSCALE_R="0.6852318156466567"

STAGEB_SPACENET_APLS="0.70278546"
STAGEB_SPACENET_TOPO="0.7937956364120718"
STAGEB_SPACENET_P="0.9320208699214366"
STAGEB_SPACENET_R="0.6912747425260352"

STAGEB_CITYSCALE_APLS="0.5609286666666667"
STAGEB_CITYSCALE_TOPO="0.7793235282360955"
STAGEB_CITYSCALE_P="0.8796706280911508"
STAGEB_CITYSCALE_R="0.7021038976908357"
# ================================

mkdir -p "$OUT_DIR"

echo "[1/3] Writing local summary CSV/JSON -> $OUT_DIR"

python3 - <<PY
import csv, json, os

out_dir = "${OUT_DIR}"
os.makedirs(out_dir, exist_ok=True)

rows = [
  {"stage":"A","dataset":"spacenet","setting":"SpaceNet 16x16 (stageA)",
   "APLS":float("${STAGEA_SPACENET_APLS}"),"TOPO":float("${STAGEA_SPACENET_TOPO}"),
   "Precision":float("${STAGEA_SPACENET_P}"),"Recall":float("${STAGEA_SPACENET_R}")},

  {"stage":"A","dataset":"cityscale","setting":"CityScale 16x16 (stageA)",
   "APLS":float("${STAGEA_CITYSCALE_APLS}"),"TOPO":float("${STAGEA_CITYSCALE_TOPO}"),
   "Precision":float("${STAGEA_CITYSCALE_P}"),"Recall":float("${STAGEA_CITYSCALE_R}")},

  {"stage":"B","dataset":"spacenet","setting":"SpaceNet 16x16 (stageB)",
   "APLS":float("${STAGEB_SPACENET_APLS}"),"TOPO":float("${STAGEB_SPACENET_TOPO}"),
   "Precision":float("${STAGEB_SPACENET_P}"),"Recall":float("${STAGEB_SPACENET_R}")},

  {"stage":"B","dataset":"cityscale","setting":"CityScale 16x16 (stageB)",
   "APLS":float("${STAGEB_CITYSCALE_APLS}"),"TOPO":float("${STAGEB_CITYSCALE_TOPO}"),
   "Precision":float("${STAGEB_CITYSCALE_P}"),"Recall":float("${STAGEB_CITYSCALE_R}")},
]

csv_path = os.path.join(out_dir, "summary_metrics.csv")
with open(csv_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["stage","dataset","setting","APLS","TOPO","Precision","Recall"])
    w.writeheader()
    w.writerows(rows)

json_path = os.path.join(out_dir, "summary_metrics.json")
with open(json_path, "w") as f:
    json.dump({"rows": rows}, f, indent=2)

print("WROTE", csv_path)
print("WROTE", json_path)
PY

echo "[2/3] Syncing to S3 -> s3://${BUCKET}/runs/<RUN>/results/ (overwrite)"

for R in "${RUNS[@]}"; do
  echo "  - ${R}"
  aws s3 sync "${OUT_DIR}/" "s3://${BUCKET}/runs/${R}/results/" --delete
done

echo "[3/3] Verify one run (list results/)"
aws s3 ls "s3://${BUCKET}/runs/${RUNS[0]}/results/" || true

echo "[OK] Published summary_metrics.csv/.json to all runs."
