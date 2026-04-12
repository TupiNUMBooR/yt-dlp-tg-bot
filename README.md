# yt-dlp-tg-bot

A Telegram bot that downloads YouTube videos using `yt-dlp`, exposes them via a temporary HTTP link, and sends the result back to Telegram.

## How it works

The project is split into simple microservices:

- **ms-ingest**
  Polls Telegram, extracts YouTube links, and creates tasks in `/app/requested`.

- **ms-downloader**
  Takes tasks from `/app/requested`, downloads files via `yt-dlp`, and moves them to `/app/downloaded`.

- **ms-server**
  Serves published files over HTTP from `/app/published/<id>`.

- **ms-cloudflared**
  Starts a Cloudflare Quick Tunnel and stores the public base URL in a shared file.

- **ms-publisher**
  Watches `/app/downloaded`, builds a public URL, moves files to `/app/published`, and sends a reply in Telegram.

## Data structure

Each task is a folder with an `info.txt`, for example:

```txt
CREATED_AT=20260412-151919
CHAT_ID=1722385747
REQUEST_MESSAGE_ID=25
SOURCE_URL=https://www.youtube.com/watch?v=JmurwMmeKY0
RESPONSE_MESSAGE_ID=
PUBLIC_URL=
FILE_NAME=Into The Void [JmurwMmeKY0].mkv
