#!/usr/bin/env bash
#MISE description="Get the address of a symbol"
set -eu -o pipefail

SYMBOL="$1"
mise run readelf-latest -- -sW | rg "$SYMBOL" | awk -v symbol="$SYMBOL" '$8 == symbol {print $2}' | head -n 1