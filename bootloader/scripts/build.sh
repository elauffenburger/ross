#!/usr/bin/env bash
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")

usage() {
  cat <<EOF
build.sh: builds bootloader
  usage: build.sh [FLAGS...]

FLAGS
  --run       if provided, qemu will be booted using the produced binary
EOF
}

BUILD_AND_RUN=
while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --run)
    BUILD_AND_RUN=1
    ;;

  *)
    echo "unknown flag $1" >&2
    usage
    ;;
  esac

  shift
done

OUT_DIR="$SCRIPT_DIR/../out"
[[ -d "$OUT_DIR" ]] || mkdir "$OUT_DIR"

echo 'building...'
nasm "$SCRIPT_DIR/../bootloader.asm" -f bin -o "$OUT_DIR/bootloader.bin"

if [[ "$BUILD_AND_RUN" == 1 ]]; then
  echo 'running...'
  qemu-system-x86_64 "$OUT_DIR/bootloader.bin"
fi
