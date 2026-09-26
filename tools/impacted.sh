#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-list}" # Modes: list, build, test
WORKSPACE_DIR="$(pwd)"
TMP_DIR="$(mktemp -d)"
STARTING_HASHES="${TMP_DIR}/starting_hashes.json"
FINAL_HASHES="${TMP_DIR}/final_hashes.json"
OUTPUT_FILE="${WORKSPACE_DIR}/impacted_targets.txt"

# 1. Build bazel-diff binary
bazel build //tools:bazel-diff --build_runfile_links
BAZEL_DIFF="./bazel-bin/tools/bazel-diff"

# 2. Find merge-base and generate base hashes
CURRENT_BRANCH=$(git rev-parse HEAD)
MERGE_BASE=$(git merge-base HEAD origin/main)

git checkout -q "$MERGE_BASE"
"$BAZEL_DIFF" generate-hashes -w "$WORKSPACE_DIR" --includeTargetType --bazelCommandOptions="--enable_workspace" "$STARTING_HASHES"

# 3. Restore branch and generate final hashes
git checkout -q "$CURRENT_BRANCH"
"$BAZEL_DIFF" generate-hashes -w "$WORKSPACE_DIR" --includeTargetType --bazelCommandOptions="--enable_workspace" "$FINAL_HASHES"

# 4. Compute diff
"$BAZEL_DIFF" get-impacted-targets -w "$WORKSPACE_DIR" --excludeExternalTargets -tt Rule -sh "$STARTING_HASHES" -fh "$FINAL_HASHES" -o "$OUTPUT_FILE"

# 5. Execute action
mapfile -t TARGETS < <(grep -v '^\s*$' "$OUTPUT_FILE" || true)

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No impacted targets found."
  exit 0
fi

case "$ACTION" in
  build)
    echo "Building ${#TARGETS[@]} target(s)..."
    bazel build "${TARGETS[@]}"
    ;;
  test)
    echo "Testing ${#TARGETS[@]} target(s)..."
    bazel test "${TARGETS[@]}"
    ;;
  list|*)
    echo "Impacted Targets:"
    printf "  %s\n" "${TARGETS[@]}"
    ;;
esac
