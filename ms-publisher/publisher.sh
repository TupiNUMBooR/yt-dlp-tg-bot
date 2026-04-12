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

read_public_base_url() {
  [ -f /app/shared/public_base_url.txt ] || return 1
  local url
  url="$(tr -d '\r' < /app/shared/public_base_url.txt | head -n 1)"
  [ -n "$url" ] || return 1
  printf '%s\n' "${url%/}"
}

format_size() {
  local bytes="$1"

  awk -v bytes="$bytes" '
    BEGIN {
      if (bytes < 1024) {
        printf "%d B\n", bytes
      } else if (bytes < 1024 * 1024) {
        printf "%.1f KB\n", bytes / 1024
      } else if (bytes < 1024 * 1024 * 1024) {
        printf "%.1f MB\n", bytes / (1024 * 1024)
      } else {
        printf "%.1f GB\n", bytes / (1024 * 1024 * 1024)
      }
    }
  '
}

edit_telegram() {
  local text="$1"

  curl --silent --show-error --fail \
    --request POST "$API_URL/editMessageText" \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "message_id=$RESPONSE_MESSAGE_ID" \
    --data-urlencode "text=$text" \
    --data "parse_mode=HTML" \
    > /dev/null
}

edit_telegram_with_retry() {
  local dir="$1"
  local text="$2"
  local i=1

  while [ "$i" -le 5 ]; do
    log "$dir" "edit try $i/5"

    if edit_telegram "$text"; then
      return 0
    fi

    i=$((i + 1))
    sleep 1
  done

  return 1
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
  FAIL_COUNT=$((FAIL_COUNT + 1))
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
  local base
  local url
  local msg
  local file_path
  local file_size_bytes
  local file_size_human

  request_id="$(basename "$dir")"

  [ -f "$f" ] || { log "$dir" "skip: no info.txt"; return 0; }

  load_info "$f"

  [ -n "$CHAT_ID" ] || { fail_current "$dir" "CHAT_ID empty"; return 0; }
  [ -n "$RESPONSE_MESSAGE_ID" ] || { fail_current "$dir" "RESPONSE_MESSAGE_ID empty"; return 0; }
  [ -n "$SOURCE_URL" ] || { fail_current "$dir" "SOURCE_URL empty"; return 0; }
  [ -n "$FILE_NAME" ] || { fail_current "$dir" "FILE_NAME empty"; return 0; }

  file_path="$dir/$FILE_NAME"
  [ -f "$file_path" ] || { fail_current "$dir" "file not found"; return 0; }

  if ! base="$(read_public_base_url)"; then
    log "$dir" "no public_url yet, will retry later"
    return 1
  fi

  file_size_bytes="$(wc -c < "$file_path" | tr -d '[:space:]')"
  file_size_human="$(format_size "$file_size_bytes")"

  url="$base/$request_id"
  msg="<a href=\"$url\">🔗 Download $file_size_human</a>"

  if ! edit_telegram_with_retry "$dir" "$msg"; then
    fail_current "$dir" "telegram edit failed"
    return 0
  fi

  PUBLIC_URL="$url"
  FAIL_COUNT="0"
  save_info "$f"

  log "$dir" "ok"

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
