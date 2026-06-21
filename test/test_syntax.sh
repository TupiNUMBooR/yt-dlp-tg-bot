#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

find ../src -type f -name '*.sh' -print0 | while IFS= read -r -d '' file; do
  bash -n "$file"
done

node --check ../src/server.js >/dev/null
