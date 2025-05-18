#!/usr/bin/env bash
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")
READELF=/opt/homebrew/opt/binutils/bin/readelf

# HACK: due to some unknown pipe shenanigans, I'm getting a signal 13 error when I try to pipe this directly to head, so here we are.
SORTED_KERNEL_ELFS=$(find "$SCRIPT_DIR/../.zig-cache" -type f -iwholename '*kernel.elf' -print0 | xargs -0 ls -tl)

"$READELF" "$(head <<<"$SORTED_KERNEL_ELFS" -n 1 | rev | cut -d ' ' -f 1 | rev)" "$@"