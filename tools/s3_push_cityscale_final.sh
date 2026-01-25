#!/usr/bin/env bash
set -euo pipefail

BUCKET="samroad-20260115-5976"

# -------- Stage A (EXISTING S3 FOLDER, REPLACE) --------
RUN_NAME_A="20260123_stageA_cityscale_16x16_stageA"
S3_A="s3://${BUCKET}/runs/${RUN_NAME_A}"

LOCAL_RUN_A="/mnt/data/outputs/20260123_stageA_cityscale_16x16_stageA"   # if missing, keep as-is
LOCAL_SAVE_A="/home/ubuntu/repos/sam_road/save/cityscale_toponet_16x16_stageA"
EVAL_LOG_A="/mnt/data/outputs/20260123_cityscale_eval_16x16_stageA.log" # optional

# -------- Stage B (NEW S3 FOLDER, REPLACE ON RE-RUN) --------
RUN_NAME_B="20260124_stageB_cityscale_cldice"
S3_B="s3://${BUCKET}/runs/${RUN_NAME_B}"

LOCAL_RUN_B="/mnt/data/outputs/20260124_stageB_cityscale_cldice"
LOCAL_SAVE_B="/home/ubuntu/repos/sam_road/save/save/cityscale_toponet_16x16_stageB_cldice"
# auto-pick latest eval log if exists
EVAL_LOG_B="$(ls -1t /mnt/data/outputs/*_cityscale_eval_stageB_cldice.log 2>/dev/null | head -n 1 || true)"

stage_sync () {
  local RUN_NAME="$1"
  local S3_PREFIX="$2"
  local LOCAL_RUN_DIR="$3"
  local LOCAL_SAVE_DIR="$4"
  local LOCAL_TRAIN_LOG="${5:-}"

  local STAGE="/mnt/data/staging_s3/${RUN_NAME}"
  echo "[INFO] staging -> ${STAGE}"
  rm -rf "${STAGE}"
  mkdir -p "${STAGE}"/{checkpoints,logs,results,save}

  if [ -d "${LOCAL_RUN_DIR}" ]; then
    echo "[INFO] run_dir: ${LOCAL_RUN_DIR}"
    [ -d "${LOCAL_RUN_DIR}/checkpoints" ] && rsync -a --delete "${LOCAL_RUN_DIR}/checkpoints/" "${STAGE}/checkpoints/"
    [ -d "${LOCAL_RUN_DIR}/logs" ]        && rsync -a --delete "${LOCAL_RUN_DIR}/logs/"        "${STAGE}/logs/"
    [ -d "${LOCAL_RUN_DIR}/results" ]     && rsync -a --delete "${LOCAL_RUN_DIR}/results/"     "${STAGE}/results/"
    [ -f "${LOCAL_RUN_DIR}/train.log" ]   && cp -f "${LOCAL_RUN_DIR}/train.log" "${STAGE}/train.log"
  else
    echo "[WARN] run_dir not found, skip: ${LOCAL_RUN_DIR}"
  fi

  if [ -d "${LOCAL_SAVE_DIR}" ]; then
    echo "[INFO] save_dir: ${LOCAL_SAVE_DIR}"
    rsync -a --delete "${LOCAL_SAVE_DIR}/" "${STAGE}/save/"
  else
    echo "[ERROR] save_dir not found: ${LOCAL_SAVE_DIR}"
    exit 2
  fi

  if [ -n "${LOCAL_TRAIN_LOG}" ] && [ -f "${LOCAL_TRAIN_LOG}" ]; then
    echo "[INFO] overwrite train.log with: ${LOCAL_TRAIN_LOG}"
    cp -f "${LOCAL_TRAIN_LOG}" "${STAGE}/train.log"
  fi

  echo "[CHECK] staged root:"
  find "${STAGE}" -maxdepth 2 -type d -print | sed 's|^|  |'
  echo "[CHECK] staged save subdirs:"
  find "${STAGE}/save" -maxdepth 1 -type d -print | sed 's|^|  |'

  echo "[S3] sync -> ${S3_PREFIX}"
  aws s3 sync "${STAGE}" "${S3_PREFIX}" --delete
  echo "[OK] done: ${RUN_NAME} -> ${S3_PREFIX}"
}

echo "===== PUSH Stage A (CityScale) ====="
stage_sync "${RUN_NAME_A}" "${S3_A}" "${LOCAL_RUN_A}" "${LOCAL_SAVE_A}" "${EVAL_LOG_A}"

echo "===== PUSH Stage B (CityScale) ====="
stage_sync "${RUN_NAME_B}" "${S3_B}" "${LOCAL_RUN_B}" "${LOCAL_SAVE_B}" "${EVAL_LOG_B}"
