#!/usr/bin/env bash
set -euo pipefail
trap 'kill -TERM 0; wait' TERM INT

API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN?}"
YT_DLP_UPDATE_INTERVAL_SECONDS="${YT_DLP_UPDATE_INTERVAL_SECONDS:-3600}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3}"

last_yt_dlp_update=0

log() {
  message="$1"
  log_file="$2"

  if [ -n "$log_file" ]; then
    printf '%s\n' "[ms-downloader] $message" | tee -a "$log_file" >&2
  else
    printf '%s\n' "$message" >&2
  fi
}

# Reads a KEY=value entry from info.txt.
read_info_value() {
  key="$1"
  info_file="$2"

  sed -n "s/^$key=//p" "$info_file" | head -n1 | tr -d '\r'
}

# Writes or replaces a KEY=value entry in info.txt.
write_info_value() {
  key="$1"
  value="$2"
  info_file="$3"

  awk -v k="$key" -v v="$value" '
    BEGIN { written=0 }
    index($0, k "=") == 1 { print k "=" v; written=1; next }
    { print }
    END { if (!written) print k "=" v }
  ' "$info_file" > "$info_file.tmp" && mv "$info_file.tmp" "$info_file"
}

# Updates an already sent Telegram message.
edit_telegram_message() {
  chat_id="$1"
  message_id="$2"
  text="$3"
  log_file="$4"

  if ! curl --silent --show-error \
    --request POST "$API_URL/editMessageText" \
    --data-urlencode "chat_id=$chat_id" \
    --data-urlencode "message_id=$message_id" \
    --data-urlencode "text=$text" \
    --data "parse_mode=HTML" \
    > /dev/null; then
    log "telegram edit failed" "$log_file"
  fi
}

# Updates yt-dlp no more often than the configured interval.
update_yt_dlp() {
  log_file="$1"
  now="$(date +%s)"

  if [ $((now - last_yt_dlp_update)) -lt "$YT_DLP_UPDATE_INTERVAL_SECONDS" ]; then
    return
  fi

  log "Updating yt-dlp" "$log_file"
  pip install -U yt-dlp --root-user-action=ignore
  last_yt_dlp_update="$now"
}

# Moves one request through the full lifecycle:
# requested -> downloading -> downloaded or failed.
process_request() {
  request_dir="$1"
  request_name="$(basename "$request_dir")"

  downloading_dir="/app/downloading/$request_name"
  downloaded_dir="/app/downloaded/$request_name"
  failed_dir="/app/failed/$request_name"

  # Claim the request before processing it.
  rm -rf "$downloading_dir"
  mv "$request_dir" "$downloading_dir"

  log_file="$downloading_dir/log.txt"
  : > "$log_file"

  info_file="$downloading_dir/info.txt"

  # Validate required request metadata.
  if [ ! -f "$info_file" ]; then
    log "no info.txt" "$log_file"
    rm -rf "$failed_dir"
    mv "$downloading_dir" "$failed_dir"
    return
  fi

  source_url="$(read_info_value SOURCE_URL "$info_file")"
  if [ -z "$source_url" ]; then
    log "empty SOURCE_URL" "$log_file"
    rm -rf "$failed_dir"
    mv "$downloading_dir" "$failed_dir"
    return
  fi

  chat_id="$(read_info_value CHAT_ID "$info_file")"
  response_message_id="$(read_info_value RESPONSE_MESSAGE_ID "$info_file")"

  if [ -z "$chat_id" ] || [ -z "$response_message_id" ]; then
    log "empty CHAT_ID or RESPONSE_MESSAGE_ID" "$log_file"
    rm -rf "$failed_dir"
    mv "$downloading_dir" "$failed_dir"
    return
  fi

  # Tell the user that the worker has started.
  edit_telegram_message "$chat_id" "$response_message_id" "⏳ Getting video…" "$log_file"

  log "start $request_name -> $source_url" "$log_file"

  attempt=1
  download_success=0
  downloaded_file_path=""

  # Retry yt-dlp a few times because network/video hosts can be flaky.
  while [ "$attempt" -le 3 ]; do
    log "try $attempt/3" "$log_file"

    downloaded_file_path="$(
      yt-dlp \
        --no-progress \
        -P "$downloading_dir" \
        --print after_move:filepath \
        -- "$source_url" \
        2>> "$log_file"
    )" || true

    if [ -n "$downloaded_file_path" ]; then
      download_success=1
      break
    fi

    attempt=$((attempt + 1))
    sleep 1
  done

  # Store the resulting file name for the uploader/next worker.
  if [ "$download_success" -eq 1 ]; then
    downloaded_file_name="$(basename "$downloaded_file_path")"
    write_info_value FILE_NAME "$downloaded_file_name" "$info_file"

    log "done -> $downloaded_file_name" "$log_file"

    rm -rf "$downloaded_dir"
    mv "$downloading_dir" "$downloaded_dir"
    return
  fi

  # Mark the request as failed after all retries.
  log "failed" "$log_file"
  edit_telegram_message "$chat_id" "$response_message_id" "❌ Failed" "$log_file"

  rm -rf "$failed_dir"
  mv "$downloading_dir" "$failed_dir"
}

main() {
  mkdir -p /app/requested /app/downloading /app/downloaded /app/failed

  while true; do
    update_yt_dlp ""

    found_request=0

    for request_dir in /app/requested/*; do
      [ -d "$request_dir" ] || continue

      found_request=1
      process_request "$request_dir"
      break
    done

    if [ "$found_request" -eq 0 ]; then
      sleep "$SLEEP_SECONDS"
    fi
  done
}

main "$@" & wait
