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

  exit 1
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

build_kernel() {
  pushd "$SCRIPT_DIR/.." >/dev/null
  zig build build-iso --summary all
  popd >/dev/null
}

main() {
  echo 'building kernel...'
  build_kernel

  if [[ "$BUILD_AND_RUN" == 1 ]]; then
    echo 'running...'
    qemu-system-x86_64 -cdrom "$SCRIPT_DIR/../zig-out/os.iso" -monitor stdio
  fi
}

main "$@"
