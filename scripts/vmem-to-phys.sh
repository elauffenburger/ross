#!/usr/bin/env bash
set -eu -o pipefail

VIRT_HEX="$1"

bw_hex() {
  local expr="$1"

  bitwise "$expr" --no-color 2>&1 | rg '^Hexadecimal: (.*)' -o -r '$1'
}

cat <<EOF
table:     $(bw_hex "$VIRT_HEX >> 22")
page:   $(bw_hex "($VIRT_HEX >> 12) & 0x03ff")
offset:  $(bw_hex "$VIRT_HEX & 0x00000fff")
EOF