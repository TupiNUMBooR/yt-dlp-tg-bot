#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
. ./assert.sh
. ../src/lib/youtube.sh

assert_eq 'JmurwMmeKY0' "$(extract_youtube_video_id 'https://www.youtube.com/watch?v=JmurwMmeKY0')" 'watch url id'
assert_eq 'JmurwMmeKY0' "$(extract_youtube_video_id 'https://www.youtube.com/watch?x=1&v=JmurwMmeKY0&t=10')" 'watch url id with params'
assert_eq 'abc_DEF-123' "$(extract_youtube_video_id 'https://youtube.com/shorts/abc_DEF-123?feature=share')" 'shorts id'
assert_eq 'abc_DEF-123' "$(extract_youtube_video_id 'https://youtu.be/abc_DEF-123?si=x')" 'youtu.be id'
assert_eq 'https://www.youtube.com/watch?v=abc_DEF-123' "$(build_youtube_watch_url 'abc_DEF-123')" 'watch url build'
assert_eq '/status' "$(normalize_command '/status@my_bot hello')" 'bot command normalize'

if extract_youtube_video_id 'not a youtube url' >/dev/null; then
  fail 'invalid url should not produce video id'
fi
