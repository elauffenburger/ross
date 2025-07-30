#!/usr/bin/env bash
set -eu -o pipefail

PSF1_FILE="$1"

echo '0:'
xxd <"$PSF1_FILE" -s 4 -b -g 2 -c 1 | cut -d ' ' -f 2 | sed 's/0/./g' |
  awk '
    {
      char_num = NR / 16;

      if (char_num < 512) {
        print;

        if (NR % 16 == 0) {
          printf("%d:\n", char_num);
        }
      }
    }
  '
