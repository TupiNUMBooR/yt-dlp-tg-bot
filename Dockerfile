FROM alpine:3.22 AS base

RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    curl \
    ffmpeg \
    findutils \
    gawk \
    grep \
    jq \
    nodejs \
    python3 \
    py3-pip \
    pipx

RUN pipx install yt-dlp
RUN pipx inject yt-dlp yt-dlp-ejs
ENV PATH="/root/.local/bin:$PATH"

RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
  && chmod +x /usr/local/bin/cloudflared

WORKDIR /app


FROM base AS test

ENV VERSION=test
ENV TELEGRAM_BOT_TOKEN=test-token
ENV DOWNLOADS_DIR=/tmp/ydtb-test-downloads
ENV SHARED_DIR=/tmp/ydtb-test-shared

COPY ./ /app/

RUN chmod +x /app/src/*.sh /app/src/bin/*.sh /app/test/*.sh

RUN /app/test/test_entrypoint.sh


FROM base AS runtime

ARG VERSION=dev
ENV VERSION=$VERSION
ENV SERVER_PORT=3000
ENV DOWNLOADS_DIR=/downloads
ENV SHARED_DIR=/app/shared

COPY --from=test /app/src/ /app/
RUN chmod +x /app/*.sh /app/bin/*.sh

EXPOSE 3000

ENTRYPOINT ["/app/entrypoint.sh"]
