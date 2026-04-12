FROM python:3.13-alpine

WORKDIR /app

RUN apk add --no-cache bash curl ffmpeg deno
RUN pip install --no-cache-dir yt-dlp yt-dlp-ejs

COPY downloader.sh /app/downloader.sh
RUN chmod +x /app/downloader.sh

CMD ["/app/downloader.sh"]
