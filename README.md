# yt-dlp-tg-bot

A Telegram bot that downloads YouTube videos using `yt-dlp`, exposes them via a temporary HTTP link, and sends the result back to Telegram.

![preview](docs/preview.jpg)

![CI/CD](https://github.com/TupiNUMBooR/yt-dlp-tg-bot/actions/workflows/ci-cd.yml/badge.svg)
![Latest Release](https://img.shields.io/github/release/TupiNUMBooR/yt-dlp-tg-bot)
![Release Date](https://img.shields.io/github/release-date/TupiNUMBooR/yt-dlp-tg-bot)

![Top Lang](https://img.shields.io/github/languages/top/TupiNUMBooR/yt-dlp-tg-bot?logo=gnubash)
![Docker](https://img.shields.io/badge/docker-ghcr-blue?logo=docker)
![Deploy](https://img.shields.io/badge/deploy-ssh-blue)

## Usage

The project is split into simple microservices:

- **ms-ingest**
  Polls Telegram, extracts YouTube links, and creates tasks in `/app/requested`.

- **ms-downloader**
  Takes tasks from `/app/requested`, downloads files via `yt-dlp`, and moves them to `/app/downloaded`.

- **ms-cloudflared**
  Starts a Cloudflare Quick Tunnel and stores the public base URL in `/app/shared`.

- **ms-publisher**
  Watches `/app/downloaded`, builds a public URL using link from `/app/shared/`, moves files to `/app/published`, and sends a reply in Telegram.

- **ms-server**
  Serves published files over HTTP from `/app/published/<id>`.

- **ms-cleaner**
  Periodically removes old files from `/app/published` and `/app/failed`.

### Data structure

Each task is a folder with an `info.txt`, for example:

```txt
CREATED_AT=20260412-151919
CHAT_ID=1722385747
REQUEST_MESSAGE_ID=25
SOURCE_URL=https://www.youtube.com/watch?v=JmurwMmeKY0
RESPONSE_MESSAGE_ID=
PUBLIC_URL=
FILE_NAME=Into The Void [JmurwMmeKY0].mkv
```

Directories:

- `/app/requested` — incoming tasks
- `/app/downloaded` — downloaded files
- `/app/published` — files served via HTTP
- `/app/failed` — failed tasks
- `/app/shared` — shared service data

## Run

### Create .env

```bash
TELEGRAM_BOT_TOKEN="123:zxc"
```

### Start

```bash
docker compose up -d --build
```

Send a link to the bot.

## Deploy

Builds Docker images and deploys them to a remote server over SSH.

### Add lines to .env

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
- update running containers with new images
