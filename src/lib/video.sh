#!/usr/bin/env bash

video_dir() {
  local video_id="$1"
  printf '%s/%s\n' "$DOWNLOADS_DIR" "$video_id"
}

video_info_file() {
  local video_id="$1"
  printf '%s/info.txt\n' "$(video_dir "$video_id")"
}

video_log_file() {
  local video_id="$1"
  printf '%s/log.txt\n' "$(video_dir "$video_id")"
}

video_requests_dir() {
  local video_id="$1"
  printf '%s/requests\n' "$(video_dir "$video_id")"
}

request_file() {
  local video_id="$1"
  local chat_id="$2"
  printf '%s/%s.txt\n' "$(video_requests_dir "$video_id")" "$chat_id"
}

now_epoch() {
  date +%s
}

now_stamp() {
  date +%Y%m%d-%H%M%S
}

set_video_status() {
  local video_id="$1"
  local status="$2"
  local info_file

  info_file="$(video_info_file "$video_id")"
  kv_set STATUS "$status" "$info_file"
  kv_set UPDATED_AT "$(now_stamp)" "$info_file"
}

extend_video_life() {
  local video_id="$1"
  local info_file current now base expires

  info_file="$(video_info_file "$video_id")"
  current="$(kv_get EXPIRES_AT_EPOCH "$info_file")"
  now="$(now_epoch)"

  if [ -n "$current" ] && [ "$current" -gt "$now" ] 2>/dev/null; then
    base="$current"
  else
    base="$now"
  fi

  expires=$((base + DOWNLOAD_TTL_SECONDS))
  kv_set EXPIRES_AT_EPOCH "$expires" "$info_file"
}

ensure_video() {
  local video_id="$1"
  local source_url="$2"
  local dir info_file

  dir="$(video_dir "$video_id")"
  info_file="$dir/info.txt"

  mkdir -p "$dir" "$dir/requests"
  touch "$dir/log.txt"

  if [ ! -f "$info_file" ]; then
    cat > "$info_file" <<EOF_INFO
VIDEO_ID=${video_id}
SOURCE_URL=${source_url}
STATUS=requested
FILE_NAME=
CREATED_AT=$(now_stamp)
UPDATED_AT=$(now_stamp)
EXPIRES_AT_EPOCH=$(($(now_epoch) + DOWNLOAD_TTL_SECONDS))
FAIL_COUNT=0
LAST_ERROR=
EOF_INFO
  fi
}

upsert_request() {
  local video_id="$1"
  local chat_id="$2"
  local request_message_id="$3"
  local file

  file="$(request_file "$video_id" "$chat_id")"
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF_REQ
CHAT_ID=${chat_id}
REQUEST_MESSAGE_ID=${request_message_id}
RESPONSE_MESSAGE_ID=
FAIL_COUNT=0
UPDATED_AT=$(now_stamp)
EOF_REQ
  else
    kv_set REQUEST_MESSAGE_ID "$request_message_id" "$file"
    kv_set RESPONSE_MESSAGE_ID "" "$file"
    kv_set FAIL_COUNT 0 "$file"
    kv_set UPDATED_AT "$(now_stamp)" "$file"
  fi
}

has_pending_requests() {
  local video_id="$1"
  find "$(video_requests_dir "$video_id")" -mindepth 1 -maxdepth 1 -type f -name '*.txt' 2>/dev/null | grep -q .
}
