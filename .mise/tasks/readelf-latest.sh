#!/usr/bin/env bash
#MISE description="Runs readelf on latest build"
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")
READELF=/opt/homebrew/opt/binutils/bin/readelf

"$READELF" "$SCRIPT_DIR/../../out/iso/boot/multiboot2.elf" "$@"
