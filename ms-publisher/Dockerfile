FROM alpine:3.22

ARG VERSION=dev
ENV VERSION=$VERSION

WORKDIR /app

RUN apk add --no-cache bash curl

COPY publisher.sh /app/publisher.sh
RUN chmod +x /app/publisher.sh

CMD ["/app/publisher.sh"]
