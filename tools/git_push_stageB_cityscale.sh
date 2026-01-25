#!/usr/bin/env bash
set -euo pipefail

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REMOTE="${1:-origin}"
MSG="${2:-"StageB CityScale: training+metrics scripts, configs, and final summary tables"}"

echo "[INFO] repo: $(pwd)"
echo "[INFO] branch: ${BRANCH}"
echo "[INFO] remote: ${REMOTE}"
echo

echo "===== git status (short) ====="
git status -sb
echo

echo "===== git diff (name-only) ====="
git diff --name-only
echo

# Recommended add set (adjust if needed)
ADD_FILES=(
  "scripts/train_stageB.py"
  "scripts/train_stageA.py"
  "config/toponet_vitb_512_cityscale_stageB_cldice.yaml"
  "cityscale_metrics/apls.bash"
  "tools/publish_summary_results.sh"
  "results/final/summary_metrics.csv"
  "results/final/summary_metrics.json"
  ".gitignore"
)

echo "[INFO] Will try to add recommended files if they exist:"
for f in "${ADD_FILES[@]}"; do
  if [ -e "$f" ]; then
    echo "  + $f"
  else
    echo "  - (skip, not found) $f"
  fi
done
echo

for f in "${ADD_FILES[@]}"; do
  [ -e "$f" ] && git add "$f" || true
done

echo "===== git status after add ====="
git status -sb
echo

# Commit only if there is something staged
if git diff --cached --quiet; then
  echo "[WARN] Nothing staged. Aborting commit."
  exit 0
fi

git commit -m "$MSG"

echo "[INFO] pushing..."
git push "$REMOTE" "$BRANCH"

echo "[OK] pushed to ${REMOTE}/${BRANCH}"
