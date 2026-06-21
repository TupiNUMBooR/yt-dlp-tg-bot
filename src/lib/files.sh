#!/usr/bin/env bash

format_size() {
  local bytes="$1"

  awk -v bytes="$bytes" '
    BEGIN {
      if (bytes < 1024) printf "%d B\n", bytes;
      else if (bytes < 1024 * 1024) printf "%.1f KB\n", bytes / 1024;
      else if (bytes < 1024 * 1024 * 1024) printf "%.1f MB\n", bytes / (1024 * 1024);
      else printf "%.1f GB\n", bytes / (1024 * 1024 * 1024);
    }
  '
}

find_downloaded_file() {
  local video_dir="$1"
  local info_file="$video_dir/info.txt"
  local file_name=""

  file_name="$(kv_get FILE_NAME "$info_file")"
  if [ -n "$file_name" ] && [ -f "$video_dir/$file_name" ]; then
    printf '%s\n' "$video_dir/$file_name"
    return 0
  fi

  find "$video_dir" -maxdepth 1 -type f \
    ! -name 'info.txt' \
    ! -name 'log.txt' \
    ! -name '*.part' \
    ! -name '*.ytdl' \
    | head -n1
}
