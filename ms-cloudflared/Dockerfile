FROM alpine:3.22

ARG VERSION=dev
ENV VERSION=$VERSION

RUN apk add --no-cache ca-certificates curl grep

# install cloudflared
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared \
  && chmod +x /usr/local/bin/cloudflared

WORKDIR /app

COPY cloudflared.sh /app/cloudflared.sh
RUN chmod +x /app/cloudflared.sh

ENTRYPOINT ["/app/cloudflared.sh"]
