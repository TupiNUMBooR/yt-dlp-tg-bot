#!/usr/bin/env bash
set -euo pipefail

trap 'kill -TERM 0; wait' TERM INT

SLEEP_SECONDS="3"
API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN:?}"

mkdir -p /app/downloaded /app/published /app/failed

log() {
  local dir="$1"
  shift
  local line
  line="[$(date +'%Y-%m-%d %H:%M:%S')] [ms-publish] $*"
  printf '%s\n' "$line" >&2
  printf '%s\n' "$line" >> "$dir/log.txt"
}

load_info() {
  local f="$1"

  CREATED_AT=""
  CHAT_ID=""
  REQUEST_MESSAGE_ID=""
  SOURCE_URL=""
  RESPONSE_MESSAGE_ID=""
  PUBLIC_URL=""
  FILE_NAME=""
  FAIL_COUNT="0"

  while IFS='=' read -r k v || [ -n "${k:-}" ]; do
    case "$k" in
      CREATED_AT) CREATED_AT="$v" ;;
      CHAT_ID) CHAT_ID="$v" ;;
      REQUEST_MESSAGE_ID) REQUEST_MESSAGE_ID="$v" ;;
      SOURCE_URL) SOURCE_URL="$v" ;;
      RESPONSE_MESSAGE_ID) RESPONSE_MESSAGE_ID="$v" ;;
      PUBLIC_URL) PUBLIC_URL="$v" ;;
      FILE_NAME) FILE_NAME="$v" ;;
      FAIL_COUNT) FAIL_COUNT="$v" ;;
    esac
  done < "$f"

  FAIL_COUNT="${FAIL_COUNT:-0}"
}

save_info() {
  local f="$1"
  cat > "$f" <<EOF
CREATED_AT=$CREATED_AT
CHAT_ID=$CHAT_ID
REQUEST_MESSAGE_ID=$REQUEST_MESSAGE_ID
SOURCE_URL=$SOURCE_URL
RESPONSE_MESSAGE_ID=$RESPONSE_MESSAGE_ID
PUBLIC_URL=$PUBLIC_URL
FILE_NAME=$FILE_NAME
FAIL_COUNT=$FAIL_COUNT
EOF
}

urlencode() {
  local s="$1" out="" c hex
  for ((i=0;i<${#s};i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v hex '%02X' "'$c"; out+="%$hex" ;;
    esac
  done
  printf '%s\n' "$out"
}

read_public_base_url() {
  [ -f /app/shared/public_base_url.txt ] || return 1
  local url
  url="$(tr -d '\r' < /app/shared/public_base_url.txt | head -n 1)"
  [ -n "$url" ] || return 1
  printf '%s\n' "${url%/}"
}

build_message() {
  local download_url="$1"
  cat <<EOF
<a href="$download_url">Download</a>
EOF
}

send_telegram() {
  curl --silent --show-error --fail \
    --request POST "$API_URL/sendMessage" \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "text=$1" \
    --data "parse_mode=HTML" \
    --data "reply_to_message_id=$REQUEST_MESSAGE_ID"
}

move_dir() {
  local src="$1"
  local dst="$2"
  local name
  name="$(basename "$src")"
  rm -rf "$dst/$name"
  mv "$src" "$dst/$name"
}

fail_current() {
  local dir="$1" reason="$2" f="$dir/info.txt"

  log "$dir" "$reason"
  FAIL_COUNT=$((FAIL_COUNT+1))
  save_info "$f"

  if [ "$FAIL_COUNT" -ge 3 ]; then
    log "$dir" "move to failed"
    move_dir "$dir" /app/failed
  fi
}

process_dir() {
  local dir="$1"
  local f="$dir/info.txt"
  local request_id

  request_id="$(basename "$dir")"

  [ -f "$f" ] || { log "$dir" "skip: no info.txt"; return 0; }

  load_info "$f"

  [ -n "$CHAT_ID" ] || { fail_current "$dir" "CHAT_ID empty"; return 0; }
  [ -n "$SOURCE_URL" ] || { fail_current "$dir" "SOURCE_URL empty"; return 0; }
  [ -n "$FILE_NAME" ] || { fail_current "$dir" "FILE_NAME empty"; return 0; }

  local base
  if ! base="$(read_public_base_url)"; then
    log "$dir" "no public_url yet, will retry later"
    return 1
  fi

  local url="$base/$(urlencode "$request_id")"
  local msg
  msg="$(build_message "$url")"

  log "$dir" "send -> $CHAT_ID"

  local resp
  if ! resp="$(send_telegram "$msg")"; then
    fail_current "$dir" "telegram failed"
    return 0
  fi

  local mid
  mid="$(printf '%s' "$resp" | sed -n 's/.*"message_id":\([0-9][0-9]*\).*/\1/p' | head -n1)"

  if [ -z "$mid" ]; then
    fail_current "$dir" "no message_id"
    return 0
  fi

  RESPONSE_MESSAGE_ID="$mid"
  PUBLIC_URL="$base"
  FAIL_COUNT="0"
  save_info "$f"

  log "$dir" "ok -> $mid"

  move_dir "$dir" /app/published
  return 0
}

main() {
  echo Started
  while true; do
    found=0
    processed=0

    for d in /app/downloaded/*; do
      [ -d "$d" ] || continue
      found=1

      if process_dir "$d"; then
        processed=1
      else
        sleep "$SLEEP_SECONDS"
      fi

      break
    done

    if [ "$found" -eq 0 ]; then
      sleep "$SLEEP_SECONDS"
    fi

    if [ "$found" -eq 1 ] && [ "$processed" -eq 0 ]; then
      :
    fi
  done
}

main & wait
