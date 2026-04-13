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
````

Directories:

* `/app/requested` — incoming tasks
* `/app/downloaded` — downloaded files
* `/app/published` — files served via HTTP
* `/app/failed` — failed tasks
* `/app/shared` — shared service data

## Run

```bash
docker compose up -d --build
```

## Requirements

Minimum:

* `TELEGRAM_BOT_TOKEN`

Optional (depending on setup):

* Cloudflare tunnel config
* mounted volumes for `/app/*` directories

## Design idea

Instead of one complex service, this is a chain of simple ones:

* receive link
* download file
* expose it
* send result

This keeps everything easy to debug, restart, and modify without turning the system into spaghetti.

## Status

Personal project.
Focused on simplicity, file-based queues, and Docker restarts rather than highload or strict architecture.

## GitHub Actions setup

This project builds Docker images on GitHub and deploys them to a remote server over SSH.

### Setup

1. Upload `.env` to the server:

```bash
./deploy/upload-env.sh
```

2. Generate deploy keys and add the public key to the server:

```bash
./deploy/setup-github-actions.sh
```

This script:

* creates `deploy/keys/github_actions`
* creates `deploy/keys/github_actions.pub`
* creates `deploy/keys/known_hosts`
* adds `deploy/keys/github_actions.pub` to `~/.ssh/authorized_keys` on the server
* verifies SSH access using the generated key

3. Add GitHub secrets:

[`Settings` → `Secrets and variables` → `Actions`](https://github.com/TupiNUMBooR/yt-dlp-tg-bot/settings/secrets/actions)

* `DEPLOY_ENABLED` = `true` (required to enable deployment)
* `SSH_ADDRESS` = value from `.env`
* `SSH_PRIVATE_KEY` = contents of `deploy/keys/github_actions`
* `SSH_KNOWN_HOSTS` = contents of `deploy/keys/known_hosts`

### How deploy works

Deploy is triggered by git tags only.

When you push a tag like:

```txt
1.0.0
```

GitHub Actions:

* builds Docker images
* pushes them to GHCR
* connects to the server over SSH
* uploads `deploy/compose.yml`
* runs deployment on the server with `TAG=1.0.0`

### Example release

```bash
git tag 1.0.0
git push
git push --tags
```
