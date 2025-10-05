#!/usr/bin/env bash
#MISE description="Decodes a psf1 file for debugging purposes"
set -eu -o pipefail

usage() {
  cat <<EOF >&2
usage: $0 [...FLAGS] FONT_FILE

FLAGS:
  --no-bitmap
  --no-table
EOF

  exit 1
}

PSF1_FILE=
PRINT_BITMAP=1
PRINT_TABLE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
  --file)
    shift
    PSF1_FILE="$1"
    ;;

  --no-bitmap)
    PRINT_BITMAP=0
    ;;

  --no-table)
    PRINT_TABLE=0
    ;;

  *)
    if [[ -z "$PSF1_FILE" ]]; then
      PSF1_FILE="$1"
    else
      echo "unknown flag $1" >&2
      usage
    fi
    ;;
  esac

  shift
done

# HACK: we make some assumptions about the file header here:
#  - char height is 16
#  - there are 512 glyphs
#  - there is a unicode lookup table

if [[ "$PRINT_BITMAP" == 1 ]]; then
  xxd <"$PSF1_FILE" -s 4 -b -g 2 -c 1 | cut -d ' ' -f 2 | sed 's/0/./g' |
    awk '
    {
      char_num = NR / 16;

      if (char_num < 512) {
        if (NR % 16 == 0 || NR == 1) {
          printf("%d:\n", char_num);
        }

        print;
      }
    }
  '
fi

if [[ "$PRINT_TABLE" == 1 ]]; then
  xxd <"$PSF1_FILE" -s $((4 + (512 * 16))) -c 2 | cut -d ' ' -f 2,3
fi
