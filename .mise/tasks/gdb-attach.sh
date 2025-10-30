#!/usr/bin/env bash
#MISE description="Attach to qemu gdb stub"
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")
gdb -ex "file $SCRIPT_DIR/../..//zig-out/bin/ross" -ex 'target remote localhost:1234' "$@"