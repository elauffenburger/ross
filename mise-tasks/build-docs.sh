#!/usr/bin/env bash
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")

docker run --rm -t \
  --entrypoint /bin/sh \
  -v "$SCRIPT_DIR/..":/app \
  -w /app \
  squidfunk/mkdocs-material -c '
pip install mkdocs-terminal

mkdocs build
'
