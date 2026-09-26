#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-list}" # Modes: list, build, test
WORKSPACE_DIR="$(pwd)"
TMP_DIR="$(mktemp -d)"
STARTING_HASHES="${TMP_DIR}/starting_hashes.json"
FINAL_HASHES="${TMP_DIR}/final_hashes.json"
OUTPUT_FILE="${WORKSPACE_DIR}/impacted_targets.txt"

# Ensure cleanup on exit
trap 'rm -rf "$TMP_DIR"' EXIT

# 1. Build bazel-diff binary
echo "[1/5] Building bazel-diff..."
bazel build //tools:bazel-diff --build_runfile_links
BAZEL_DIFF="./bazel-bin/tools/bazel-diff"

# 2. Find merge-base and generate base hashes
CURRENT_BRANCH=$(git rev-parse HEAD)
MERGE_BASE=$(git merge-base HEAD origin/main)

echo "[2/5] Generating base hashes for $MERGE_BASE..."
git checkout -q "$MERGE_BASE"
"$BAZEL_DIFF" generate-hashes \
  -w "$WORKSPACE_DIR" \
  --includeTargetType \
  --excludeExternalTargets \
  "$STARTING_HASHES"

# 3. Restore branch and generate final hashes
echo "[3/5] Restoring HEAD ($CURRENT_BRANCH) and generating head hashes..."
git checkout -q "$CURRENT_BRANCH"
"$BAZEL_DIFF" generate-hashes \
  -w "$WORKSPACE_DIR" \
  --includeTargetType \
  --excludeExternalTargets \
  "$FINAL_HASHES"

# 4. Compute diff
echo "[4/5] Computing impacted targets..."
"$BAZEL_DIFF" get-impacted-targets \
  -w "$WORKSPACE_DIR" \
  --excludeExternalTargets \
  -tt Rule \
  -sh "$STARTING_HASHES" \
  -fh "$FINAL_HASHES" \
  -o "$OUTPUT_FILE"

# 5. Read targets into an array (macOS / Bash 3.2 compatible)
TARGETS=()
if [ -f "$OUTPUT_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" ]] && continue
    TARGETS+=("$line")
  done < "$OUTPUT_FILE"
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No impacted rule targets found."
  exit 0
fi

case "$ACTION" in
  build)
    echo "[5/5] Building ${#TARGETS[@]} impacted target(s)..."
    bazel build "${TARGETS[@]}"
    ;;
  test)
    echo "[5/5] Testing ${#TARGETS[@]} impacted target(s)..."
    bazel test "${TARGETS[@]}"
    ;;
  list|*)
    echo "=== Impacted Rule Targets ==="
    printf "%s\n" "${TARGETS[@]}"
    echo "============================="
    ;;
esac
