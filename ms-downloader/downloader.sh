#!/usr/bin/env bash
set -euo pipefail
trap 'kill -TERM 0; wait' TERM INT

API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN?}"
YT_DLP_UPDATE_INTERVAL_SECONDS="${YT_DLP_UPDATE_INTERVAL_SECONDS:-3600}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3}"

last_update=0
LOG_FILE=""

log() {
  msg="$*"

  if [ -n "$LOG_FILE" ]; then
    printf '%s\n' "[ms-downloader] $msg" | tee -a "$LOG_FILE" >&2
  else
    printf '%s\n' "$msg" >&2
  fi
}

get() {
  sed -n "s/^$1=//p" "$2" | head -n1 | tr -d '\r'
}

set_kv() {
  key="$1"
  val="$2"
  file="$3"

  awk -v k="$key" -v v="$val" '
    BEGIN { done=0 }
    index($0, k "=") == 1 { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

edit_telegram_message() {
  chat_id="$1"
  message_id="$2"
  text="$3"

  if ! curl --silent --show-error \
    --request POST "$API_URL/editMessageText" \
    --data-urlencode "chat_id=$chat_id" \
    --data-urlencode "message_id=$message_id" \
    --data-urlencode "text=$text" \
    --data "parse_mode=HTML" \
    > /dev/null; then
    log "telegram edit failed"
  fi
}

update_yt_dlp() {
  now="$(date +%s)"

  if [ $((now - last_update)) -lt "$YT_DLP_UPDATE_INTERVAL_SECONDS" ]; then
    return
  fi

  log "Updating yt-dlp"
  pip install -U yt-dlp --root-user-action=ignore
  last_update="$now"
}

process() {
  req="$1"
  name="$(basename "$req")"

  down="/app/downloading/$name"
  done="/app/downloaded/$name"
  fail="/app/failed/$name"

  rm -rf "$down"
  mv "$req" "$down"

  LOG_FILE="$down/log.txt"
  : > "$LOG_FILE"

  info="$down/info.txt"

  if [ ! -f "$info" ]; then
    log "no info.txt"
    rm -rf "$fail"
    mv "$down" "$fail"
    return
  fi

  url="$(get SOURCE_URL "$info")"
  if [ -z "$url" ]; then
    log "empty SOURCE_URL"
    rm -rf "$fail"
    mv "$down" "$fail"
    return
  fi

  chat_id="$(get CHAT_ID "$info")"
  response_message_id="$(get RESPONSE_MESSAGE_ID "$info")"

  if [ -z "$chat_id" ] || [ -z "$response_message_id" ]; then
    log "empty CHAT_ID or RESPONSE_MESSAGE_ID"
    rm -rf "$fail"
    mv "$down" "$fail"
    return
  fi

  edit_telegram_message "$chat_id" "$response_message_id" "⏳ Getting video…"

  log "start $name -> $url"

  i=1
  ok=0
  file_path=""

  while [ "$i" -le 3 ]; do
    log "try $i/3"

    file_path="$(
      yt-dlp \
        --no-progress \
        -P "$down" \
        --print after_move:filepath \
        -- "$url" \
        2>> "$LOG_FILE"
    )" || true

    if [ -n "$file_path" ]; then
      ok=1
      break
    fi

    i=$((i + 1))
    sleep 1
  done

  if [ "$ok" -eq 1 ]; then
    file_name="$(basename "$file_path")"
    set_kv FILE_NAME "$file_name" "$info"

    log "done -> $file_name"

    rm -rf "$done"
    mv "$down" "$done"
    return
  fi

  log "failed"
  edit_telegram_message "$chat_id" "$response_message_id" "❌ Failed"

  rm -rf "$fail"
  mv "$down" "$fail"
}

mkdir -p /app/requested /app/downloading /app/downloaded /app/failed

while true; do
  update_yt_dlp

  found=0

  for d in /app/requested/*; do
    [ -d "$d" ] || continue
    found=1
    process "$d"
    break
  done

  if [ "$found" -eq 0 ]; then
    sleep "$SLEEP_SECONDS"
  fi
done & wait
