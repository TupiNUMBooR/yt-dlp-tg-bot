#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

for test_file in test_*.sh; do
  [ "$test_file" != "test_entrypoint.sh" ] || continue
  printf '[test] %s\n' "$test_file"
  bash "$test_file"
done

printf '[test] all ok\n'
