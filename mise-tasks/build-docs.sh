#!/usr/bin/env bash
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")

INTERACTIVE=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
  -i)
    INTERACTIVE=1
    ;;

  *)
    echo "unknown flag $1" >&2
    exit 1
    ;;
  esac
done

ARGS=(run --rm -it -v "$SCRIPT_DIR/..":/app -w /app)
if [[ "$INTERACTIVE" == 1 ]]; then
  ARGS+=(--entrypoint /bin/sh squidfunk/mkdocs-material)
else
  ARGS+=(squidfunk/mkdocs-material build)
fi

docker "${ARGS[@]}"
