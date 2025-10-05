#!/usr/bin/env bash
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")

FILES_REGEX='.*/[^/]*\.\(o\)'

ALL_FILES=$(find "$SCRIPT_DIR/../../.zig-cache" -type f -regex "$FILES_REGEX" -exec stat -f '%m,%N' {} \;)
UNIQ_FILENAMES=$(cut <<<"$ALL_FILES" -d ',' -f 2 | xargs -I{} basename {} | sort | uniq)

while read -r filename; do
  rg <<<"$ALL_FILES" "$filename\$" | sort -rn | head -n 1 | cut -d ',' -f 2
done <<<"$UNIQ_FILENAMES"
