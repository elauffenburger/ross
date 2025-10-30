#!/usr/bin/env bash
#MISE description="Get latest version of an output in .zig-cache/"
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")
find "$SCRIPT_DIR/../../.zig-cache" -type f -iwholename "$1" -print0 | xargs -0 ls -lt | head -n 1 | awk '{ print $NF }'