# yt-dlp-tg-bot

A Telegram bot that downloads YouTube videos using `yt-dlp`, exposes them through a temporary Cloudflare tunnel, and sends the download link back to Telegram.

<img src="docs/preview.jpg" height="400">

![CI/CD](https://github.com/TupiNUMBooR/yt-dlp-tg-bot/actions/workflows/ci-cd.yml/badge.svg)
![Latest Release](https://img.shields.io/github/release/TupiNUMBooR/yt-dlp-tg-bot)
![Release Date](https://img.shields.io/github/release-date/TupiNUMBooR/yt-dlp-tg-bot)

![Top Lang](https://img.shields.io/github/languages/top/TupiNUMBooR/yt-dlp-tg-bot?logo=gnubash)
![Docker](https://img.shields.io/badge/docker-ghcr-blue?logo=docker)
![Deploy](https://img.shields.io/badge/deploy-ssh-blue)

## How it works

The bot is one Docker container with small internal workers. Source code lives in `src/`, tests live in `test/`.

- **ingest-worker.sh** polls Telegram, extracts YouTube links, creates video folders, and subscribes chats to updates.
- **downloader-worker.sh** downloads requested videos with `yt-dlp`.
- **notifier-worker.sh** sends or edits Telegram status messages for active requests.
- **cloudflared-worker.sh** starts a Cloudflare Quick Tunnel and writes the public URL to `/app/shared/public-base-url.txt`.
- **server.js** serves downloaded files from `/downloads`.
- **cleaner-worker.sh** removes old downloaded or failed videos.

Video state lives in `/downloads/<video_id>/info.txt`.
Active Telegram requests live in `/downloads/<video_id>/requests/<chat_id>.txt` and are removed after a final success or failure message.

### Video structure

```txt
/downloads/JmurwMmeKY0/
  info.txt
  log.txt
  Into The Void [JmurwMmeKY0].mkv
  requests/
    1722385747.txt
```

### Video statuses

```txt
requested
downloading
downloaded
failed
```

### info.txt example

```txt
VIDEO_ID=JmurwMmeKY0
SOURCE_URL=https://www.youtube.com/watch?v=JmurwMmeKY0
STATUS=downloaded
FILE_NAME=Into The Void [JmurwMmeKY0].mkv
CREATED_AT=20260621-153022
UPDATED_AT=20260621-153122
EXPIRES_AT_EPOCH=1782051082
FAIL_COUNT=0
LAST_ERROR=
```

### request file example

```txt
CHAT_ID=1722385747
REQUEST_MESSAGE_ID=25
RESPONSE_MESSAGE_ID=26
FAIL_COUNT=0
UPDATED_AT=20260621-153100
```


### Project structure

```txt
src/
  entrypoint.sh
  server.js
  bin/
    ingest-worker.sh
    downloader-worker.sh
    notifier-worker.sh
    cleaner-worker.sh
    cloudflared-worker.sh
  lib/
    config.sh
    log.sh
    kv.sh
    youtube.sh
    files.sh
    video.sh
    telegram.sh
    notify.sh

test/
  test_entrypoint.sh
  test_*.sh
```

Tests are written with the same rule as the app: `test -> ../src`.

Run them locally:

```bash
./test/test_entrypoint.sh
```

Or run them through Docker build:

```bash
docker build --target test .
```

## Run

### Create `.env`

```bash
TELEGRAM_BOT_TOKEN="123:zxc"
```

### Start

```bash
docker compose up -d --build
```

Send a [YouTube link](https://youtu.be/4uhRJO3v52U) to the bot.

## Deploy

Builds a Docker image and deploys it to a remote server over SSH.

### Add lines to `.env`

```bash
SSH_ADDRESS=user@11.11.11.11
REMOTE_DIR="~/ydtb"
```

- `SSH_ADDRESS` — deploy target (`user@host`)
- `REMOTE_DIR` — deploy directory on the server

Note:

- be careful with `REMOTE_DIR` — paths with spaces may not work, check script usage

### Upload `.env` to the server

```bash
./deploy/upload-env.sh
```

### Setup deploy SSH access

```bash
./deploy/setup-deploy-access.sh
```

Creates:

- `deploy/keys/github_actions` (private key)
- `deploy/keys/github_actions.pub` (public key)
- `deploy/keys/known_hosts`

Also:

- adds the public key to `~/.ssh/authorized_keys` on the server
- verifies SSH access

### Configure [GitHub Actions](https://github.com/TupiNUMBooR/yt-dlp-tg-bot/settings/secrets/actions)

Variables:

- `DEPLOY_ENABLED` = `true`
- `REMOTE_DIR` = same as in deploy `.env`

Secrets:

- `SSH_ADDRESS` = from deploy `.env`
- `SSH_PRIVATE_KEY` = contents of `deploy/keys/github_actions`
- `SSH_KNOWN_HOSTS` = contents of `deploy/keys/known_hosts`

### Release

```bash
git tag 1.0.0
git push
git push --tags
```

GitHub Actions will:

- build Docker images (`latest`, `1.0`, `1.0.0`)
- push them to GHCR
- connect to the server over SSH
- upload `deploy/compose.yml`
- update the running container
