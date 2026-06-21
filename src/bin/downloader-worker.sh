#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

. "$APP_DIR/lib/config.sh"
. "$APP_DIR/lib/log.sh"
. "$APP_DIR/lib/kv.sh"
. "$APP_DIR/lib/files.sh"
. "$APP_DIR/lib/video.sh"
. "$APP_DIR/lib/telegram.sh"
. "$APP_DIR/lib/notify.sh"

last_yt_dlp_update=0

update_yt_dlp() {
  local now
  now="$(date +%s)"

  if [ $((now - last_yt_dlp_update)) -lt "$YT_DLP_UPDATE_INTERVAL_SECONDS" ]; then
    return 0
  fi

  log "downloader" "updating yt-dlp"
  pipx upgrade yt-dlp >/dev/null
  pipx runpip yt-dlp install -U yt-dlp-ejs >/dev/null
  last_yt_dlp_update="$now"
}

reconcile_downloads() {
  local info_file video_id status

  for info_file in "$DOWNLOADS_DIR"/*/info.txt; do
    [ -f "$info_file" ] || continue
    video_id="$(kv_get VIDEO_ID "$info_file")"
    status="$(kv_get STATUS "$info_file")"
    if [ -n "$video_id" ] && [ "$status" = "downloading" ]; then
      log_to_file "downloader" "$(video_log_file "$video_id")" "restore stale downloading -> requested"
      set_video_status "$video_id" requested
      notify_video_requests "$video_id"
    fi
  done
}

next_requested_video() {
  local info_file status video_id

  for info_file in "$DOWNLOADS_DIR"/*/info.txt; do
    [ -f "$info_file" ] || continue
    status="$(kv_get STATUS "$info_file")"
    [ "$status" = "requested" ] || continue
    video_id="$(kv_get VIDEO_ID "$info_file")"
    [ -n "$video_id" ] || continue
    printf '%s\n' "$video_id"
    return 0
  done

  return 1
}

process_video() {
  local video_id="$1"
  local dir info_file log_file source_url attempt downloaded_file_path file_name fail_count

  dir="$(video_dir "$video_id")"
  info_file="$dir/info.txt"
  log_file="$dir/log.txt"
  source_url="$(kv_get SOURCE_URL "$info_file")"

  if [ -z "$source_url" ]; then
    kv_set LAST_ERROR "empty SOURCE_URL" "$info_file"
    set_video_status "$video_id" failed
    notify_video_requests "$video_id"
    return 0
  fi

  set_video_status "$video_id" downloading
  notify_video_requests "$video_id"
  log_to_file "downloader" "$log_file" "start $video_id -> $source_url"

  attempt=1
  downloaded_file_path=""

  while [ "$attempt" -le "$MAX_DOWNLOAD_FAILS" ]; do
    log_to_file "downloader" "$log_file" "try $attempt/$MAX_DOWNLOAD_FAILS"

    downloaded_file_path="$(
      yt-dlp \
        --js-runtimes node \
        --no-progress \
        --no-playlist \
        -P "$dir" \
        -o '%(title).200B [%(id)s].%(ext)s' \
        --print after_move:filepath \
        -- "$source_url" \
        2>> "$log_file"
    )" || true

    if [ -n "$downloaded_file_path" ] && [ -f "$downloaded_file_path" ]; then
      file_name="$(basename "$downloaded_file_path")"
      kv_set FILE_NAME "$file_name" "$info_file"
      kv_set FAIL_COUNT 0 "$info_file"
      kv_set LAST_ERROR "" "$info_file"
      set_video_status "$video_id" downloaded
      log_to_file "downloader" "$log_file" "done -> $file_name"
      notify_video_requests "$video_id"
      return 0
    fi

    fail_count="$(kv_get FAIL_COUNT "$info_file")"
    fail_count="${fail_count:-0}"
    fail_count=$((fail_count + 1))
    kv_set FAIL_COUNT "$fail_count" "$info_file"
    kv_set LAST_ERROR "yt-dlp failed" "$info_file"

    attempt=$((attempt + 1))
    sleep 1
  done

  set_video_status "$video_id" failed
  log_to_file "downloader" "$log_file" "failed"
  notify_video_requests "$video_id"
}

main() {
  local video_id

  mkdir -p "$DOWNLOADS_DIR"
  reconcile_downloads
  log "downloader" "started"

  while true; do
    update_yt_dlp

    if video_id="$(next_requested_video)"; then
      process_video "$video_id"
    else
      sleep "$SLEEP_SECONDS"
    fi
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
