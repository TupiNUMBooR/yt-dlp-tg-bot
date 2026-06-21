#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

. "$APP_DIR/lib/config.sh"
. "$APP_DIR/lib/log.sh"
. "$APP_DIR/lib/kv.sh"
. "$APP_DIR/lib/files.sh"
. "$APP_DIR/lib/video.sh"
. "$APP_DIR/lib/telegram.sh"
. "$APP_DIR/lib/notify.sh"

notify_once() {
  local dir video_id

  for dir in "$DOWNLOADS_DIR"/*; do
    [ -d "$dir" ] || continue
    video_id="$(basename "$dir")"
    has_pending_requests "$video_id" || continue
    notify_video_requests "$video_id"
  done
}

main() {
  mkdir -p "$DOWNLOADS_DIR"
  log "notifier" "started"

  while true; do
    notify_once
    sleep "$SLEEP_SECONDS"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
