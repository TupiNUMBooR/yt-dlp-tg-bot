FROM node:24-alpine

ARG VERSION=dev
ENV VERSION=$VERSION
WORKDIR /app

COPY server.js /app/server.js

EXPOSE 3000

CMD ["node", "/app/server.js"]
