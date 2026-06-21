#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./assert.sh

export TELEGRAM_BOT_TOKEN=test-token
export DOWNLOADS_DIR="$(mktemp -d)"
export SHARED_DIR="$(mktemp -d)"
export PUBLIC_BASE_URL_FILE="$SHARED_DIR/public-base-url.txt"
export MAX_NOTIFY_FAILS=2

. ../src/lib/config.sh
. ../src/lib/kv.sh
. ../src/lib/log.sh
. ../src/lib/files.sh
. ../src/lib/video.sh
. ../src/lib/notify.sh

mkdir -p "$SHARED_DIR"
printf 'https://example.trycloudflare.com\n' > "$PUBLIC_BASE_URL_FILE"
ensure_video 'JmurwMmeKY0' 'https://www.youtube.com/watch?v=JmurwMmeKY0'
info="$(video_info_file 'JmurwMmeKY0')"

assert_eq '⏳ Queued...' "$(build_status_message 'JmurwMmeKY0')" 'requested message'
set_video_status 'JmurwMmeKY0' downloading
assert_eq '📥 Downloading...' "$(build_status_message 'JmurwMmeKY0')" 'downloading message'
set_video_status 'JmurwMmeKY0' failed
assert_eq '💀 Failed to download.' "$(build_status_message 'JmurwMmeKY0')" 'failed message'

set_video_status 'JmurwMmeKY0' downloaded
kv_set FILE_NAME 'Into The Void [JmurwMmeKY0].mkv' "$info"
printf 'video-data' > "$(video_dir 'JmurwMmeKY0')/Into The Void [JmurwMmeKY0].mkv"
message="$(build_status_message 'JmurwMmeKY0')"
case "$message" in
  *'https://example.trycloudflare.com/JmurwMmeKY0'*'Download'*) ;;
  *) fail "downloaded message should contain public URL: $message" ;;
esac
can_finalize_video 'JmurwMmeKY0' || fail 'downloaded video with URL should be finalizable'

upsert_request 'JmurwMmeKY0' '1722385747' '25'
req="$(request_file 'JmurwMmeKY0' '1722385747')"

telegram_edit_message() { return 1; }
telegram_send_message() {
  local chat_id="$1"
  local text="$2"
  local reply_to="${3:-}"
  assert_eq '1722385747' "$chat_id" 'telegram send chat id'
  assert_not_empty "$text" 'telegram send text'
  assert_eq '25' "$reply_to" 'telegram reply id'
  printf '777\n'
}

notify_request_file 'JmurwMmeKY0' "$req" "$message" 0
assert_file_exists "$req"
assert_eq '777' "$(kv_get RESPONSE_MESSAGE_ID "$req")" 'new response message id stored'

notify_request_file 'JmurwMmeKY0' "$req" "$message" 1
assert_file_not_exists "$req"

upsert_request 'JmurwMmeKY0' '1722385747' '25'
req="$(request_file 'JmurwMmeKY0' '1722385747')"
telegram_send_message() { return 1; }
notify_request_file 'JmurwMmeKY0' "$req" "$message" 1 || true
assert_file_exists "$req"
notify_request_file 'JmurwMmeKY0' "$req" "$message" 1 || true
assert_file_not_exists "$req"
