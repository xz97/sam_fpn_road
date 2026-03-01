#!/usr/bin/env bash
set -euo pipefail

RUN_NAME="${1:?Usage: $0 <RUN_NAME> <PRED_DIR_ABS>}"
PRED_DIR="${2:?Usage: $0 <RUN_NAME> <PRED_DIR_ABS>}"

RUN_DIR="/mnt/data/outputs/$RUN_NAME"
S3_BASE="s3://samroad-20260115-5976/runs/$RUN_NAME"

echo "[S3] RUN_NAME=$RUN_NAME"
echo "[S3] RUN_DIR =$RUN_DIR"
echo "[S3] PRED_DIR=$PRED_DIR"
echo "[S3] S3_BASE =$S3_BASE"

test -d "$RUN_DIR" || { echo "[ERR] missing RUN_DIR: $RUN_DIR"; exit 2; }
test -d "$PRED_DIR" || { echo "[ERR] missing PRED_DIR: $PRED_DIR"; exit 3; }

aws s3 sync "$RUN_DIR" "$S3_BASE/" --delete
aws s3 sync "$PRED_DIR" "$S3_BASE/save/$(basename "$PRED_DIR")/" --delete

# optional: copy summaries to run root for quick browsing
if [[ -f "$PRED_DIR/eval/apls/apls_summary.log" ]]; then
  aws s3 cp "$PRED_DIR/eval/apls/apls_summary.log" "$S3_BASE/apls_summary.log"
fi
if [[ -f "$PRED_DIR/eval/topo/topo_summary_from_txt.csv" ]]; then
  aws s3 cp "$PRED_DIR/eval/topo/topo_summary_from_txt.csv" "$S3_BASE/topo_summary_from_txt.csv"
fi
if [[ -f "$PRED_DIR/eval/topo/topo_summary_from_txt.log" ]]; then
  aws s3 cp "$PRED_DIR/eval/topo/topo_summary_from_txt.log" "$S3_BASE/topo_summary_from_txt.log"
fi

echo "[OK] S3 sync done."
