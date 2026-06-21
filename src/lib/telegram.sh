#!/usr/bin/env bash

telegram_log() {
  if declare -F log >/dev/null 2>&1; then
    log "$@"
  else
    printf '%s\n' "$*" >&2
  fi
}

telegram_api_post() {
  local method="$1"
  shift

  local body_file=""
  local http_code=""
  local response=""

  body_file="$(mktemp)"

  if ! http_code="$(
    curl --silent --show-error \
      --request POST "$API_URL/$method" \
      "$@" \
      --output "$body_file" \
      --write-out '%{http_code}'
  )"; then
    response="$(cat "$body_file" 2>/dev/null || true)"
    rm -f "$body_file"

    telegram_log "telegram $method request failed: ${response:-curl failed without response body}"
    return 1
  fi

  response="$(cat "$body_file" 2>/dev/null || true)"
  rm -f "$body_file"

  if jq -e '.ok == true' >/dev/null 2>&1 <<< "$response"; then
    printf '%s\n' "$response"
    return 0
  fi

  telegram_log "telegram $method failed: http=$http_code response=${response:-empty response}"
  return 1
}

telegram_send_message() {
  local chat_id="$1"
  local text="$2"
  local reply_to_message_id="${3:-}"
  local response=""

  if [ -n "$reply_to_message_id" ]; then
    response="$(
      telegram_api_post "sendMessage" \
        --data-urlencode "chat_id=$chat_id" \
        --data-urlencode "text=$text" \
        --data "parse_mode=HTML" \
        --data "reply_to_message_id=$reply_to_message_id"
    )" || return 1
  else
    response="$(
      telegram_api_post "sendMessage" \
        --data-urlencode "chat_id=$chat_id" \
        --data-urlencode "text=$text" \
        --data "parse_mode=HTML"
    )" || return 1
  fi

  jq -r '.result.message_id // empty' <<< "$response"
}

telegram_edit_message() {
  local chat_id="$1"
  local message_id="$2"
  local text="$3"

  local body_file=""
  local http_code=""
  local response=""
  local description=""

  body_file="$(mktemp)"

  if ! http_code="$(
    curl --silent --show-error \
      --request POST "$API_URL/editMessageText" \
      --data-urlencode "chat_id=$chat_id" \
      --data-urlencode "message_id=$message_id" \
      --data-urlencode "text=$text" \
      --data "parse_mode=HTML" \
      --output "$body_file" \
      --write-out '%{http_code}'
  )"; then
    response="$(cat "$body_file" 2>/dev/null || true)"
    rm -f "$body_file"

    telegram_log "telegram editMessageText request failed: ${response:-curl failed without response body}"
    return 1
  fi

  response="$(cat "$body_file" 2>/dev/null || true)"
  rm -f "$body_file"

  if jq -e '.ok == true' >/dev/null 2>&1 <<< "$response"; then
    return 0
  fi

  description="$(jq -r '.description // empty' <<< "$response" 2>/dev/null || true)"

  if printf '%s\n' "$description" | grep -qi 'message is not modified'; then
    return 0
  fi

  telegram_log "telegram editMessageText failed: http=$http_code response=${response:-empty response}"
  return 1
}

telegram_delete_message() {
  local chat_id="$1"
  local message_id="$2"

  telegram_api_post "deleteMessage" \
    --data-urlencode "chat_id=$chat_id" \
    --data-urlencode "message_id=$message_id" \
    >/dev/null
}
