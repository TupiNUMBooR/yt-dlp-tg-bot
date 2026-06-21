#!/usr/bin/env bash

read_public_base_url() {
  [ -f "$PUBLIC_BASE_URL_FILE" ] || return 1
  local url
  url="$(tr -d '\r' < "$PUBLIC_BASE_URL_FILE" | head -n1)"
  [ -n "$url" ] || return 1
  printf '%s\n' "${url%/}"
}

build_video_url() {
  local video_id="$1"
  local base

  base="$(read_public_base_url)" || return 1
  printf '%s/%s\n' "$base" "$video_id"
}

build_status_message() {
  local video_id="$1"
  local info_file status file_path file_size_bytes file_size_human url

  info_file="$(video_info_file "$video_id")"
  status="$(kv_get STATUS "$info_file")"

  case "$status" in
    requested)
      printf '⏳ Queued...\n'
      ;;
    downloading)
      printf '📥 Downloading...\n'
      ;;
    downloaded)
      file_path="$(find_downloaded_file "$(video_dir "$video_id")")"
      if [ -z "$file_path" ]; then
        printf '💀 Downloaded, but file is missing.\n'
        return 0
      fi
      file_size_bytes="$(wc -c < "$file_path" | tr -d '[:space:]')"
      file_size_human="$(format_size "$file_size_bytes")"
      url="$(build_video_url "$video_id")" || {
        printf '✅ Downloaded. Waiting for public URL...\n'
        return 0
      }
      printf '<a href="%s">💾 Download</a> %s\n' "$url" "$file_size_human"
      ;;
    failed)
      printf '💀 Failed to download.\n'
      ;;
    *)
      printf '⏳ Queued...\n'
      ;;
  esac
}

can_finalize_video() {
  local video_id="$1"
  local info_file status file_path

  info_file="$(video_info_file "$video_id")"
  status="$(kv_get STATUS "$info_file")"

  if [ "$status" = "failed" ]; then
    return 0
  fi

  if [ "$status" != "downloaded" ]; then
    return 1
  fi

  file_path="$(find_downloaded_file "$(video_dir "$video_id")")"
  [ -n "$file_path" ] || return 1
  read_public_base_url >/dev/null || return 1
}

notify_request_file() {
  local video_id="$1"
  local req_file="$2"
  local text="$3"
  local final="$4"
  local log_file chat_id request_message_id response_message_id fail_count new_message_id status

  log_file="$(video_log_file "$video_id")"
  chat_id="$(kv_get CHAT_ID "$req_file")"
  request_message_id="$(kv_get REQUEST_MESSAGE_ID "$req_file")"
  response_message_id="$(kv_get RESPONSE_MESSAGE_ID "$req_file")"
  fail_count="$(kv_get FAIL_COUNT "$req_file")"
  fail_count="${fail_count:-0}"

  if [ -z "$chat_id" ]; then
    log_to_file "notify" "$log_file" "skip request without CHAT_ID: $req_file"
    rm -f "$req_file"
    return 0
  fi

  if [ -n "$response_message_id" ]; then
    if telegram_edit_message "$chat_id" "$response_message_id" "$text"; then
      kv_set FAIL_COUNT 0 "$req_file"
      kv_set UPDATED_AT "$(now_stamp)" "$req_file"
      if [ "$final" = "1" ]; then
        rm -f "$req_file"
      fi
      return 0
    fi
    log_to_file "notify" "$log_file" "edit failed for chat=$chat_id message=$response_message_id, will send new"
  fi

  if new_message_id="$(telegram_send_message "$chat_id" "$text" "$request_message_id")" && [ -n "$new_message_id" ]; then
    kv_set RESPONSE_MESSAGE_ID "$new_message_id" "$req_file"
    kv_set FAIL_COUNT 0 "$req_file"
    kv_set UPDATED_AT "$(now_stamp)" "$req_file"
    if [ "$final" = "1" ]; then
      rm -f "$req_file"
    fi
    return 0
  fi

  fail_count=$((fail_count + 1))
  kv_set FAIL_COUNT "$fail_count" "$req_file"
  kv_set UPDATED_AT "$(now_stamp)" "$req_file"
  log_to_file "notify" "$log_file" "send failed for chat=$chat_id fail_count=$fail_count"

  if [ "$fail_count" -ge "$MAX_NOTIFY_FAILS" ]; then
    log_to_file "notify" "$log_file" "remove dead request: $req_file"
    rm -f "$req_file"
  fi
}

notify_video_requests() {
  local video_id="$1"
  local info_file status text final req_file

  info_file="$(video_info_file "$video_id")"
  [ -f "$info_file" ] || return 0

  status="$(kv_get STATUS "$info_file")"
  text="$(build_status_message "$video_id")"
  final=0
  can_finalize_video "$video_id" && final=1

  for req_file in "$(video_requests_dir "$video_id")"/*.txt; do
    [ -f "$req_file" ] || continue
    notify_request_file "$video_id" "$req_file" "$text" "$final"
  done
}

send_immediate_video_result() {
  local video_id="$1"
  local chat_id="$2"
  local request_message_id="$3"
  local text

  text="$(build_status_message "$video_id")"
  telegram_send_message "$chat_id" "$text" "$request_message_id" >/dev/null
}
