#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./assert.sh

export TELEGRAM_BOT_TOKEN=test-token
export DOWNLOADS_DIR="$(mktemp -d)"
export SHARED_DIR="$(mktemp -d)"
export DOWNLOAD_TTL_SECONDS=86400

. ../src/lib/config.sh
. ../src/lib/kv.sh
. ../src/lib/video.sh

kv_file="$DOWNLOADS_DIR/kv.txt"
kv_set FOO bar "$kv_file"
assert_eq 'bar' "$(kv_get FOO "$kv_file")" 'kv set creates key'
kv_set FOO baz "$kv_file"
assert_eq 'baz' "$(kv_get FOO "$kv_file")" 'kv set replaces key'
kv_append ITEM one "$kv_file"
kv_append ITEM two "$kv_file"
assert_eq 'one' "$(kv_get ITEM "$kv_file")" 'kv get returns first repeated key'

ensure_video 'JmurwMmeKY0' 'https://www.youtube.com/watch?v=JmurwMmeKY0'
info="$(video_info_file 'JmurwMmeKY0')"
assert_file_exists "$info"
assert_eq 'requested' "$(kv_get STATUS "$info")" 'new video status'
assert_eq 'JmurwMmeKY0' "$(kv_get VIDEO_ID "$info")" 'video id stored'
assert_file_exists "$(video_log_file 'JmurwMmeKY0')"

old_expires="$(kv_get EXPIRES_AT_EPOCH "$info")"
extend_video_life 'JmurwMmeKY0'
new_expires="$(kv_get EXPIRES_AT_EPOCH "$info")"
[ "$new_expires" -gt "$old_expires" ] || fail 'extend_video_life should increase EXPIRES_AT_EPOCH'

upsert_request 'JmurwMmeKY0' '1722385747' '25'
req="$(request_file 'JmurwMmeKY0' '1722385747')"
assert_file_exists "$req"
assert_eq '1722385747' "$(kv_get CHAT_ID "$req")" 'request chat id'
assert_eq '25' "$(kv_get REQUEST_MESSAGE_ID "$req")" 'request message id'

kv_set RESPONSE_MESSAGE_ID 99 "$req"
upsert_request 'JmurwMmeKY0' '1722385747' '31'
assert_eq '31' "$(kv_get REQUEST_MESSAGE_ID "$req")" 'request message updates'
assert_eq '' "$(kv_get RESPONSE_MESSAGE_ID "$req")" 'response message resets for new request'

has_pending_requests 'JmurwMmeKY0' || fail 'pending requests should exist'
rm -f "$req"
if has_pending_requests 'JmurwMmeKY0'; then
  fail 'pending requests should not exist after deletion'
fi
