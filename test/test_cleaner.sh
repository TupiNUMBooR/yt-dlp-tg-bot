#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./assert.sh

export TELEGRAM_BOT_TOKEN=test-token
export DOWNLOADS_DIR="$(mktemp -d)"
export SHARED_DIR="$(mktemp -d)"
export DOWNLOAD_TTL_SECONDS=86400

. ../src/bin/cleaner-worker.sh

ensure_video 'oldvideo' 'https://www.youtube.com/watch?v=oldvideo'
info="$(video_info_file 'oldvideo')"
set_video_status 'oldvideo' downloaded
kv_set EXPIRES_AT_EPOCH 1 "$info"

can_delete_video 'oldvideo' || fail 'expired downloaded video without requests should be deletable'

upsert_request 'oldvideo' '1722385747' '25'
if can_delete_video 'oldvideo'; then
  fail 'video with pending request should not be deletable'
fi
rm -f "$(request_file 'oldvideo' '1722385747')"

set_video_status 'oldvideo' downloading
if can_delete_video 'oldvideo'; then
  fail 'downloading video should not be deletable'
fi

set_video_status 'oldvideo' failed
cleanup_once
[ ! -d "$(video_dir 'oldvideo')" ] || fail 'cleanup_once should remove expired failed/downloaded video'
