#!/usr/bin/env bash
set -euo pipefail
trap 'kill -TERM 0; wait' TERM INT

REQUESTED_DIR="/app/requested"
API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN?}"

mkdir -p "$REQUESTED_DIR"

log() {
  printf '%s\n' "$*" >&2
}

generate_id() {
  head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

count_dirs() {
  local dir="$1"

  find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

send_message() {
  local chat_id="$1"
  local text="$2"
  local reply_to_message_id="${3:-}"

  if [[ -n "$reply_to_message_id" ]]; then
    curl --silent --show-error --fail \
      --request POST "$API_URL/sendMessage" \
      --data-urlencode "chat_id=$chat_id" \
      --data-urlencode "text=$text" \
      --data "parse_mode=HTML" \
      --data "reply_to_message_id=$reply_to_message_id" \
      >/dev/null
  else
    curl --silent --show-error --fail \
      --request POST "$API_URL/sendMessage" \
      --data-urlencode "chat_id=$chat_id" \
      --data-urlencode "text=$text" \
      --data "parse_mode=HTML" \
      >/dev/null
  fi
}

normalize_command() {
  local text="$1"

  printf '%s\n' "$text" | sed -nE 's#^(/[a-zA-Z0-9_]+)(@[a-zA-Z0-9_]+)?([[:space:]].*)?$#\1#p'
}

normalize_youtube_url() {
  local raw_url="$1"
  local video_id=""

  video_id="$(printf '%s\n' "$raw_url" | sed -nE 's#^https?://(www\.)?youtube\.com/watch\?([^#]*&)?v=([^&]+).*$#\3#p')"
  [[ -n "$video_id" ]] && {
    printf 'https://www.youtube.com/watch?v=%s\n' "$video_id"
    return 0
  }

  video_id="$(printf '%s\n' "$raw_url" | sed -nE 's#^https?://(www\.)?youtube\.com/shorts/([^?&#/]+).*$#\2#p')"
  [[ -n "$video_id" ]] && {
    printf 'https://www.youtube.com/watch?v=%s\n' "$video_id"
    return 0
  }

  video_id="$(printf '%s\n' "$raw_url" | sed -nE 's#^https?://youtu\.be/([^?&#/]+).*$#\1#p')"
  [[ -n "$video_id" ]] && {
    printf 'https://www.youtube.com/watch?v=%s\n' "$video_id"
    return 0
  }

  return 1
}

send_status() {
  local chat_id="$1"
  local request_message_id="$2"
  local requested_count=""
  local downloaded_count=""
  local published_count=""
  local failed_count=""

  requested_count="$(count_dirs /app/requested)"
  downloaded_count="$(count_dirs /app/downloaded)"
  published_count="$(count_dirs /app/published)"
  failed_count="$(count_dirs /app/failed)"

  send_message "$chat_id" "📊 Status

⏳ Requested: ${requested_count}
📥 Downloaded: ${downloaded_count}
✅ Published: ${published_count}
💀 Failed: ${failed_count}" "$request_message_id"
}

create_job() {
  local update_json="$1"
  local chat_id=""
  local request_message_id=""
  local source_url_raw=""
  local command=""
  local source_url=""
  local created_at=""
  local job_id=""
  local job_dir=""
  local response_json=""
  local response_message_id=""

  chat_id="$(jq -r '.message.chat.id // empty' <<< "$update_json")"
  request_message_id="$(jq -r '.message.message_id // empty' <<< "$update_json")"
  source_url_raw="$(jq -r '.message.text // empty' <<< "$update_json")"

  [[ -n "$chat_id" ]] || return 0
  [[ -n "$request_message_id" ]] || return 0
  [[ -n "$source_url_raw" ]] || return 0

  command="$(normalize_command "$source_url_raw")"

  if [[ "$command" == "/start" ]]; then
    send_message "$chat_id" "Send me a YouTube link, and I will return a download." "$request_message_id"
    return 0
  fi

  if [[ "$command" == "/status" ]]; then
    send_status "$chat_id" "$request_message_id"
    return 0
  fi

  source_url="$(normalize_youtube_url "$source_url_raw")" || return 0

  created_at="$(date +%Y%m%d-%H%M%S)"
  job_id="$(generate_id)"
  job_dir="${REQUESTED_DIR}/${job_id}"

  mkdir -p "$job_dir"
  : > "${job_dir}/log.txt"

  response_json="$(
    curl --silent --show-error --fail \
      --request POST "$API_URL/sendMessage" \
      --data-urlencode "chat_id=$chat_id" \
      --data-urlencode "text=⏳ Queued..." \
      --data "parse_mode=HTML" \
      --data "reply_to_message_id=$request_message_id"
  )"

  response_message_id="$(jq -r '.result.message_id // empty' <<< "$response_json")"
  [[ -n "$response_message_id" ]]

  cat > "${job_dir}/info.txt" <<EOF
CREATED_AT=${created_at}
CHAT_ID=${chat_id}
REQUEST_MESSAGE_ID=${request_message_id}
RESPONSE_MESSAGE_ID=${response_message_id}
SOURCE_URL=${source_url}
EOF

  log "Created job: ${job_id} -> ${source_url}"
}

main() {
  local response=""
  local update=""
  local offset=0

  log "Started"

  while true; do
    if ! response="$(
      curl -fsS --get "${API_URL}/getUpdates" \
        --data-urlencode "timeout=30" \
        --data-urlencode "offset=${offset}"
    )"; then
      log "getUpdates failed"
      sleep 2
      continue
    fi

    [[ "$(jq -r '.ok' <<< "$response")" == "true" ]] || continue

    while IFS= read -r update; do
      [[ -n "$update" ]] || continue
      offset=$(( $(jq -r '.update_id' <<< "$update") + 1 ))
      create_job "$update"
    done < <(jq -c '.result[]?' <<< "$response")
  done
}

main & wait
