FROM alpine:3.22

ARG VERSION=dev
ENV VERSION=$VERSION
RUN apk add --no-cache bash ca-certificates coreutils curl jq

WORKDIR /app

COPY ingest.sh /app/ingest.sh
RUN chmod +x /app/ingest.sh

CMD ["/app/ingest.sh"]
