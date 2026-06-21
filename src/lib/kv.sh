#!/usr/bin/env bash

# Reads the first KEY=value entry from a small metadata file.
kv_get() {
  local key="$1"
  local file="$2"

  [ -f "$file" ] || return 0
  sed -n "s/^${key}=//p" "$file" | head -n1 | tr -d '\r'
}

# Writes or replaces a KEY=value entry in a small metadata file.
kv_set() {
  local key="$1"
  local value="$2"
  local file="$3"
  local dir

  dir="$(dirname "$file")"
  mkdir -p "$dir"
  touch "$file"

  awk -v k="$key" -v v="$value" '
    BEGIN { written=0 }
    index($0, k "=") == 1 { print k "=" v; written=1; next }
    { print }
    END { if (!written) print k "=" v }
  ' "$file" > "${file}.tmp"
  mv "${file}.tmp" "$file"
}

kv_append() {
  local key="$1"
  local value="$2"
  local file="$3"

  mkdir -p "$(dirname "$file")"
  printf '%s=%s\n' "$key" "$value" >> "$file"
}
