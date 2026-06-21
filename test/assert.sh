#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-values differ}"

  if [ "$expected" != "$actual" ]; then
    printf 'FAIL: %s\nexpected: <%s>\nactual:   <%s>\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_file_exists() {
  local file="$1"
  [ -f "$file" ] || fail "expected file to exist: $file"
}

assert_file_not_exists() {
  local file="$1"
  [ ! -f "$file" ] || fail "expected file to be removed: $file"
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_empty() {
  local value="$1"
  local message="${2:-expected non-empty value}"
  [ -n "$value" ] || fail "$message"
}
