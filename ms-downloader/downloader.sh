#!/usr/bin/env bash
set -euo pipefail

YT_DLP_UPDATE_INTERVAL_SECONDS="${YT_DLP_UPDATE_INTERVAL_SECONDS:-3600}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3}"

last_update=0
LOG_FILE=""

log() {
  msg="$*"

  if [ -n "$LOG_FILE" ]; then
    printf '%s\n' "[ms-downloader] $msg" | tee -a "$LOG_FILE" >&2
  else
    printf '%s\n' "$msg" >&2
  fi
}

get() {
  sed -n "s/^$1=//p" "$2" | head -n1 | tr -d '\r'
}

set_kv() {
  key="$1"
  val="$2"
  file="$3"

  awk -v k="$key" -v v="$val" '
    BEGIN { done=0 }
    index($0, k "=") == 1 { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

update_yt_dlp() {
  now="$(date +%s)"

  if [ $((now - last_update)) -lt "$YT_DLP_UPDATE_INTERVAL_SECONDS" ]; then
    return
  fi

  log "Updating yt-dlp"
  pip install -U yt-dlp --root-user-action=ignore
  last_update="$now"
}

process() {
  req="$1"
  name="$(basename "$req")"

  down="/app/downloading/$name"
  done="/app/downloaded/$name"
  fail="/app/failed/$name"

  rm -rf "$down"
  mv "$req" "$down"

  LOG_FILE="$down/log.txt"
  : > "$LOG_FILE"

  info="$down/info.txt"

  if [ ! -f "$info" ]; then
    log "no info.txt"
    rm -rf "$fail"
    mv "$down" "$fail"
    return
  fi

  url="$(get SOURCE_URL "$info")"
  if [ -z "$url" ]; then
    log "empty SOURCE_URL"
    rm -rf "$fail"
    mv "$down" "$fail"
    return
  fi

  log "start $name -> $url"

  i=1
  ok=0
  file_path=""

  while [ "$i" -le 3 ]; do
    log "try $i/3"

    file_path="$(
      yt-dlp \
        --no-progress \
        -P "$down" \
        --print after_move:filepath \
        -- "$url" \
        2>> "$LOG_FILE"
    )" || true

    if [ -n "$file_path" ]; then
      ok=1
      break
    fi

    i=$((i + 1))
    sleep 1
  done

  if [ "$ok" -eq 1 ]; then
    file_name="$(basename "$file_path")"
    set_kv FILE_NAME "$file_name" "$info"

    log "done -> $file_name"

    rm -rf "$done"
    mv "$down" "$done"
    return
  fi

  log "failed"

  rm -rf "$fail"
  mv "$down" "$fail"
}

mkdir -p /app/requested /app/downloading /app/downloaded /app/failed

while true; do
  update_yt_dlp

  found=0

  for d in /app/requested/*; do
    [ -d "$d" ] || continue
    found=1
    process "$d"
    break
  done

  if [ "$found" -eq 0 ]; then
    sleep "$SLEEP_SECONDS"
  fi
done
