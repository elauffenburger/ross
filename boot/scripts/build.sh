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
OUTPUT_TYPE=iso
while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --run)
    BUILD_AND_RUN=1
    ;;

  --output)
    shift

    OUTPUT_TYPE="$1"
    ;;

  *)
    echo "unknown flag $1" >&2
    usage
    ;;
  esac

  shift
done

if [[ ! ("$OUTPUT_TYPE" == elf || "$OUTPUT_TYPE" == iso) ]]; then
  echo "unexpected --output-type $OUTPUT_TYPE" >&2
  usage
fi

ensure_dir() {
  local dir="$1"

  [[ -d "$dir" ]] || mkdir -p "$dir"
}

OUT_DIR="$SCRIPT_DIR/../out"
ensure_dir "$OUT_DIR"

build_kernel() {
  build_rust_kernel() {
    pushd "$SCRIPT_DIR/../../"

    local target=x86_64-ross
    cargo build --target "$target.json"

    local ross_obj_archive="target/$target/debug/libross.a"
    local ross_obj_files=$(tar -tf "$ross_obj_archive" | rg '\.o$' | tr '\n' ' ')
    tar -xf "$ross_obj_archive" -C "$OUT_DIR/obj" $ross_obj_files

    popd
  }

  build_loader() {
    local object_files="$SCRIPT_DIR/../asm/*.s"
    for obj_file in $object_files; do
      nasm "$obj_file" -f elf32 -o "$OUT_DIR/obj/$(rev <<<"$obj_file" | cut -d '/' -f 1 | cut -c 3- | rev).o"
    done

    x86_64-linux-gnu-ld \
      -T "$SCRIPT_DIR/../link.ld" \
      -m elf_i386 \
      -o "$OUT_DIR/kernel.elf" \
      "$OUT_DIR"/obj/*.o
  }

  [[ -d "$OUT_DIR/obj" ]] && rm -rf "$OUT_DIR/obj"
  mkdir -p "$OUT_DIR/obj"

  # build_rust_kernel
  build_loader
}

build_iso() {
  ensure_dir "$OUT_DIR/iso"
  ensure_dir "$OUT_DIR/iso/boot"
  ensure_dir "$OUT_DIR/iso/boot/grub"

  if [[ ! -f "$OUT_DIR/iso/boot/grub/stage2_eltorito" ]]; then
    set -x
    echo 'downloading GRUB stage2_eltorito...'
    wget https://littleosbook.github.io/files/stage2_eltorito -O "$OUT_DIR/iso/boot/grub/stage2_eltorito"
  fi

  cp "$OUT_DIR/kernel.elf" "$OUT_DIR/iso/boot"
  cat <<EOF >"$OUT_DIR/iso/boot/grub/menu.lst"
default=0
timeout=0

title os
kernel /boot/kernel.elf
EOF

  mkisofs -quiet \
    -input-charset utf8 \
    -eltorito-boot boot/grub/stage2_eltorito \
    -boot-info-table \
    -boot-load-size 4 \
    -rock \
    -no-emul-boot \
    -o "$OUT_DIR/os.iso" \
    -A os \
    "$OUT_DIR/iso"
}

main() {
  echo 'building kernel...'
  build_kernel

  if [[ "$OUTPUT_TYPE" == iso ]]; then
    echo 'building iso...'
    build_iso
  fi

  if [[ "$BUILD_AND_RUN" == 1 ]]; then
    echo 'running...'

    case "$OUTPUT_TYPE" in
    elf)
      qemu-system-x86_64 -kernel "$OUT_DIR/kernel.elf" -monitor stdio
      ;;

    iso)
      qemu-system-x86_64 -cdrom "$OUT_DIR/os.iso" -monitor stdio
      ;;

    *)
      echo "unknown --output-type $OUTPUT_TYPE" >&2
      usage
      ;;
    esac
  fi
}

main "$@"
