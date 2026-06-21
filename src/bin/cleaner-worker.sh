#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

. "$APP_DIR/lib/config.sh"
. "$APP_DIR/lib/log.sh"
. "$APP_DIR/lib/kv.sh"
. "$APP_DIR/lib/video.sh"

can_delete_video() {
  local video_id="$1"
  local info_file status expires now

  info_file="$(video_info_file "$video_id")"
  [ -f "$info_file" ] || return 1

  status="$(kv_get STATUS "$info_file")"
  case "$status" in
    downloaded|failed) ;;
    *) return 1 ;;
  esac

  if has_pending_requests "$video_id"; then
    return 1
  fi

  expires="$(kv_get EXPIRES_AT_EPOCH "$info_file")"
  [ -n "$expires" ] || return 1

  now="$(date +%s)"
  [ "$now" -gt "$expires" ] 2>/dev/null
}

cleanup_once() {
  local dir video_id

  for dir in "$DOWNLOADS_DIR"/*; do
    [ -d "$dir" ] || continue
    video_id="$(basename "$dir")"

    if can_delete_video "$video_id"; then
      log_to_file "cleaner" "$(video_log_file "$video_id")" "delete expired video"
      rm -rf "$dir"
    fi
  done
}

main() {
  mkdir -p "$DOWNLOADS_DIR"
  log "cleaner" "started"

  while true; do
    cleanup_once
    sleep "$CLEANUP_INTERVAL_SECONDS"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
