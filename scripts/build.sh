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
MONITOR=
START_GDB=
VERBOSE=
while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --run)
    BUILD_AND_RUN=1
    ;;

  --monitor)
    MONITOR=1
    ;;

  --gdb)
    START_GDB=1
    ;;

  --verbose)
    VERBOSE=1
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

  ZIG_ARGS=(
    --summary all
    --color on
  )
  if [[ "$VERBOSE" == 1 ]]; then
    ZIG_ARGS+=(
      --verbose-link
    )

    # --verbose-link               Enable compiler debug output for linking
    # --verbose-air                Enable compiler debug output for Zig AIR
    # --verbose-llvm-ir[=file]     Enable compiler debug output for LLVM IR
    # --verbose-llvm-bc=[file]     Enable compiler debug output for LLVM BC
    # --verbose-cimport            Enable compiler debug output for C imports
    # --verbose-cc                 Enable compiler debug output for C compilation
    # --verbose-llvm-cpu-features  Enable compiler debug output for LLVM CPU features
  fi

  zig build build-iso "${ZIG_ARGS[@]}"

  popd >/dev/null
}

main() {
  echo 'building kernel...'
  build_kernel

  if [[ "$BUILD_AND_RUN" == 1 ]]; then
    echo 'running...'

    QEMU_ARGS=(
      -accel 'tcg,thread=single'
      -cpu 'core2duo,-lm'
      -m 128
      -smp 1
      -usb
      -device usb-kbd
      -device 'usb-host,hostbus=0,hostaddr=1'
      -vga std
      -cdrom "$SCRIPT_DIR/../zig-out/os.iso"
      -no-reboot
      -d 'cpu_reset,int,guest_errors,page,in_asm,pcall'
      -D /tmp/qemu-monitor
    )

    if [[ "$START_GDB" == 1 ]]; then
      QEMU_ARGS+=(-s -S)
    fi

    if [[ "$MONITOR" == 1 ]]; then
      QEMU_ARGS+=(-monitor stdio)
    else
      QEMU_ARGS+=(-serial stdio)
    fi

    qemu-system-i386 "${QEMU_ARGS[@]}"
  fi
}

main "$@"
