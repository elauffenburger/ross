#!/usr/bin/env bash
#MISE description="Build and run OS image"
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")
ROOT_DIR="$SCRIPT_DIR/../../"
OUT_DIR="$ROOT_DIR/out"

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
  pushd "$ROOT_DIR" >/dev/null

  ZIG_ARGS=(
    --summary all
    --color on

    -freference-trace=100
  )
  if [[ "$VERBOSE" == 1 ]]; then
    # --verbose-link               Enable compiler debug output for linking
    # --verbose-air                Enable compiler debug output for Zig AIR
    # --verbose-llvm-ir[=file]     Enable compiler debug output for LLVM IR
    # --verbose-llvm-bc=[file]     Enable compiler debug output for LLVM BC
    # --verbose-cimport            Enable compiler debug output for C imports
    # --verbose-cc                 Enable compiler debug output for C compilation
    # --verbose-llvm-cpu-features  Enable compiler debug output for LLVM CPU features

    ZIG_ARGS+=(
      --verbose-link
    )
  fi

  zig build "${ZIG_ARGS[@]}"

  popd >/dev/null
}

build_iso() {
  local limine_dir="$ROOT_DIR/vendor/limine"

  pushd "$OUT_DIR" 2>/dev/null

  # Copy our boot dir over.
  mkdir -p iso/boot
  cp -r -v "$ROOT_DIR/boot"/* iso/boot/

  # Copy ross binary over.
  cp -v "$ROOT_DIR/zig-out/bin/ross" iso/boot/multiboot2.elf

  # Copy limine files over.
  mkdir -p iso/boot/limine
  cp -v "$limine_dir/"{limine-bios.sys,limine-bios-cd.bin,limine-uefi-cd.bin} iso/boot/limine/

  # Copy limine EFI files over.
  mkdir -p iso/EFI/BOOT
  cp -v "$limine_dir/"{BOOTX64.EFI,BOOTIA32.EFI} iso/EFI/BOOT/

  # Create the bootable ISO.
  xorriso \
    -as mkisofs \
    -R -r -J \
    -b boot/limine/limine-bios-cd.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -hfsplus \
    -apm-block-size 2048 \
    --efi-boot boot/limine/limine-uefi-cd.bin \
    -efi-boot-part \
    --efi-boot-image \
    --protective-msdos-label \
    -o os.iso \
    iso

  # Install Limine stage 1 and 2 for legacy BIOS boot.
  "$limine_dir/limine" bios-install os.iso

  popd 2>/dev/null
}

main() {
  [[ -d "$OUT_DIR" ]] && rm -rf "$OUT_DIR"
  mkdir -p "$OUT_DIR"

  echo 'building kernel...'
  build_kernel

  echo 'building iso...'
  build_iso

  if [[ "$BUILD_AND_RUN" == 1 ]]; then
    echo 'running...'

    QEMU_ARGS=(
      -cpu 'max'
      -accel 'tcg,thread=single'
      # -object 'memory-backend-file,id=pc.ram,size=512M,mem-path=/tmp/qemu-memory,prealloc=on,share=on'
      # -machine memory-backend=pc.ram
      -m 4096M
      -vga std
      -cdrom "$OUT_DIR/os.iso"
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
