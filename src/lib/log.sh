#!/usr/bin/env bash

log() {
  local component="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$component" "$*" >&2
}

log_to_file() {
  local component="$1"
  local log_file="$2"
  shift 2
  local line

  line="[$(date +'%Y-%m-%d %H:%M:%S')] [${component}] $*"
  printf '%s\n' "$line" >&2
  if [ -n "$log_file" ]; then
    mkdir -p "$(dirname "$log_file")"
    printf '%s\n' "$line" >> "$log_file"
  fi
}
