#!/usr/bin/env sh
set -eu
trap 'kill -TERM 0; wait' TERM INT

: "${TUNNEL_URL:?}"

URL_FILE="/app/shared/public_base_url.txt"

rm -f "$URL_FILE"

echo "Starting tunnel to $TUNNEL_URL"

cloudflared tunnel --no-autoupdate --metrics 0.0.0.0:20241 --url "$TUNNEL_URL" 2>&1 \
  | tee /dev/stdout \
  | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' \
  | while read -r url; do
      echo "$url" > "$URL_FILE"
      echo "Url: $url"
    done & wait
