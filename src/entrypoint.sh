#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

. "$APP_DIR/lib/config.sh"
. "$APP_DIR/lib/log.sh"

pids=""

shutdown() {
  log "entrypoint" "shutdown"
  trap - TERM INT
  if [ -n "$pids" ]; then
    kill -TERM $pids 2>/dev/null || true
  fi
  wait || true
  exit 0
}

supervise() {
  local name="$1"
  shift
  local child=""

  trap 'if [ -n "$child" ]; then kill -TERM "$child" 2>/dev/null || true; fi; exit 0' TERM INT

  while true; do
    log "entrypoint" "start $name"
    "$@" &
    child="$!"
    wait "$child" || true
    child=""
    log "entrypoint" "$name stopped, restarting"
    sleep 2
  done
}

start_worker() {
  local name="$1"
  shift

  supervise "$name" "$@" &
  pids="$pids $!"
}

main() {
  mkdir -p "$DOWNLOADS_DIR" "$SHARED_DIR"

  trap shutdown TERM INT

  start_worker server node "$APP_DIR/server.js"
  start_worker cloudflared "$APP_DIR/bin/cloudflared-worker.sh"
  start_worker ingest "$APP_DIR/bin/ingest-worker.sh"
  start_worker downloader "$APP_DIR/bin/downloader-worker.sh"
  start_worker notifier "$APP_DIR/bin/notifier-worker.sh"
  start_worker cleaner "$APP_DIR/bin/cleaner-worker.sh"

  wait
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
