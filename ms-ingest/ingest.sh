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

normalize_youtube_url() {
  local raw_url="$1"
  local video_id=""

  video_id="$(printf '%s\n' "$raw_url" | sed -nE 's#^https?://(www\.)?youtube\.com/watch\?([^#]*&)?v=([^&]+).*$#\3#p')"
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

create_job() {
  local update_json="$1"
  local chat_id=""
  local request_message_id=""
  local source_url_raw=""
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
      --data-urlencode "text=⏳ Queued" \
      --data "parse_mode=HTML" \
      --data "reply_to_message_id=$request_message_id"
  )"

  response_message_id="$(jq -r '.result.message_id // empty' <<< "$response_json")"
  [[ -n "$response_message_id" ]]

  # потом сразу пишем готовый info.txt без перезаписей
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
