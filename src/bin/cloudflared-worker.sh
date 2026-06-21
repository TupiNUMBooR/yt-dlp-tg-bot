#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

. "$APP_DIR/lib/config.sh"
. "$APP_DIR/lib/log.sh"

main() {
  mkdir -p "$SHARED_DIR"
  rm -f "$PUBLIC_BASE_URL_FILE"

  log "cloudflared" "starting tunnel to $TUNNEL_URL"

  cloudflared tunnel --no-autoupdate --metrics 0.0.0.0:20241 --url "$TUNNEL_URL" 2>&1 \
    | tee /dev/stderr \
    | grep --line-buffered -oE 'https://[a-z0-9-]+\.trycloudflare\.com' \
    | while IFS= read -r url; do
        printf '%s\n' "$url" > "$PUBLIC_BASE_URL_FILE"
        log "cloudflared" "url: $url"
      done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
