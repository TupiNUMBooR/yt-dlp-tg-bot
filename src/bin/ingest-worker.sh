#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

. "$APP_DIR/lib/config.sh"
. "$APP_DIR/lib/log.sh"
. "$APP_DIR/lib/kv.sh"
. "$APP_DIR/lib/youtube.sh"
. "$APP_DIR/lib/files.sh"
. "$APP_DIR/lib/video.sh"
. "$APP_DIR/lib/telegram.sh"
. "$APP_DIR/lib/notify.sh"

count_videos_by_status() {
  local status="$1"
  local count=0
  local info_file current

  for info_file in "$DOWNLOADS_DIR"/*/info.txt; do
    [ -f "$info_file" ] || continue
    current="$(kv_get STATUS "$info_file")"
    [ "$current" = "$status" ] && count=$((count + 1))
  done

  printf '%s\n' "$count"
}

send_status() {
  local chat_id="$1"
  local request_message_id="$2"

  telegram_send_message "$chat_id" "📊 Status

🧩 Version: ${VERSION}

⏳ Requested: $(count_videos_by_status requested)
📥 Downloading: $(count_videos_by_status downloading)
✅ Downloaded: $(count_videos_by_status downloaded)
💀 Failed: $(count_videos_by_status failed)" "$request_message_id" >/dev/null
}

handle_video_request() {
  local chat_id="$1"
  local request_message_id="$2"
  local raw_url="$3"
  local video_id source_url status

  video_id="$(extract_youtube_video_id "$raw_url")" || return 0
  source_url="$(build_youtube_watch_url "$video_id")"

  ensure_video "$video_id" "$source_url"
  extend_video_life "$video_id"

  status="$(kv_get STATUS "$(video_info_file "$video_id")")"

  case "$status" in
    downloaded|failed)
      if can_finalize_video "$video_id" && send_immediate_video_result "$video_id" "$chat_id" "$request_message_id"; then
        log_to_file "ingest" "$(video_log_file "$video_id")" "immediate reply chat=$chat_id message=$request_message_id status=$status"
      else
        upsert_request "$video_id" "$chat_id" "$request_message_id"
        log_to_file "ingest" "$(video_log_file "$video_id")" "request chat=$chat_id message=$request_message_id status=$status"
        notify_video_requests "$video_id"
      fi
      ;;
    *)
      upsert_request "$video_id" "$chat_id" "$request_message_id"
      log_to_file "ingest" "$(video_log_file "$video_id")" "request chat=$chat_id message=$request_message_id status=$status"
      notify_video_requests "$video_id"
      ;;
  esac
}

handle_update() {
  local update_json="$1"
  local chat_id request_message_id text command

  chat_id="$(jq -r '.message.chat.id // empty' <<< "$update_json")"
  request_message_id="$(jq -r '.message.message_id // empty' <<< "$update_json")"
  text="$(jq -r '.message.text // empty' <<< "$update_json")"

  [ -n "$chat_id" ] || return 0
  [ -n "$request_message_id" ] || return 0
  [ -n "$text" ] || return 0

  command="$(normalize_command "$text")"

  case "$command" in
    /start)
      telegram_send_message "$chat_id" "Send me a YouTube link, and I will return a download." "$request_message_id" >/dev/null
      return 0
      ;;
    /status)
      send_status "$chat_id" "$request_message_id"
      return 0
      ;;
  esac

  handle_video_request "$chat_id" "$request_message_id" "$text"
}

main() {
  local response update offset=0

  mkdir -p "$DOWNLOADS_DIR" "$SHARED_DIR"
  log "ingest" "started"

  while true; do
    if ! response="$(
      curl -fsS --get "${API_URL}/getUpdates" \
        --data-urlencode "timeout=30" \
        --data-urlencode "offset=${offset}"
    )"; then
      log "ingest" "getUpdates failed"
      sleep 2
      continue
    fi

    [ "$(jq -r '.ok' <<< "$response")" = "true" ] || continue

    while IFS= read -r update; do
      [ -n "$update" ] || continue
      offset=$(( $(jq -r '.update_id' <<< "$update") + 1 ))
      handle_update "$update"
    done < <(jq -c '.result[]?' <<< "$response")
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
