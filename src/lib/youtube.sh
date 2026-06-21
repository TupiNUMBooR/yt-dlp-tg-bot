#!/usr/bin/env bash

extract_youtube_video_id() {
  local raw_url="$1"
  local video_id=""

  video_id="$(printf '%s\n' "$raw_url" | sed -nE 's#^https?://(www\.)?youtube\.com/watch\?([^#]*&)?v=([^&]+).*$#\3#p')"
  [ -n "$video_id" ] && { printf '%s\n' "$video_id"; return 0; }

  video_id="$(printf '%s\n' "$raw_url" | sed -nE 's#^https?://(www\.)?youtube\.com/shorts/([^?&#/]+).*$#\2#p')"
  [ -n "$video_id" ] && { printf '%s\n' "$video_id"; return 0; }

  video_id="$(printf '%s\n' "$raw_url" | sed -nE 's#^https?://youtu\.be/([^?&#/]+).*$#\1#p')"
  [ -n "$video_id" ] && { printf '%s\n' "$video_id"; return 0; }

  return 1
}

build_youtube_watch_url() {
  local video_id="$1"
  printf 'https://www.youtube.com/watch?v=%s\n' "$video_id"
}

normalize_command() {
  local text="$1"
  printf '%s\n' "$text" | sed -nE 's#^(/[a-zA-Z0-9_]+)(@[a-zA-Z0-9_]+)?([[:space:]].*)?$#\1#p'
}
