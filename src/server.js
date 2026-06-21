const http = require("http");
const fs = require("fs");
const path = require("path");

const HOST = "0.0.0.0";
const PORT = Number(process.env.SERVER_PORT || process.env.PORT || 3000);
const DOWNLOADS_DIR = process.env.DOWNLOADS_DIR || "/downloads";

function log(...args) {
  console.log("[server]", ...args);
}

function parseInfoFile(infoPath) {
  const result = {};
  const raw = fs.readFileSync(infoPath, "utf8");

  for (const line of raw.split("\n")) {
    const idx = line.indexOf("=");
    if (idx === -1) continue;
    result[line.slice(0, idx)] = line.slice(idx + 1);
  }

  return result;
}

function sendText(res, statusCode, text) {
  res.writeHead(statusCode, {
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(text);
}

function buildContentDisposition(fileName) {
  const safeName = fileName
    .replace(/[<>:"/\\|?*\x00-\x1F]/g, "_")
    .trim();

  const fallback = safeName
    .replace(/["\\]/g, "_")
    .replace(/[^\x20-\x7E]/g, "_");

  return `attachment; filename="${fallback}"; filename*=UTF-8''${encodeURIComponent(safeName)}`;
}

function findFileFromInfo(videoDir, info) {
  if (info.FILE_NAME) {
    const filePath = path.join(videoDir, info.FILE_NAME);
    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) return filePath;
  }

  for (const name of fs.readdirSync(videoDir)) {
    if (name === "info.txt" || name === "log.txt" || name === "requests") continue;
    if (name.endsWith(".part") || name.endsWith(".ytdl")) continue;

    const filePath = path.join(videoDir, name);
    if (fs.statSync(filePath).isFile()) return filePath;
  }

  return null;
}

const server = http.createServer((req, res) => {
  log(req.method, req.url);

  if (req.method !== "GET") {
    sendText(res, 405, "Method Not Allowed");
    return;
  }

  const reqPath = new URL(req.url, "http://localhost").pathname;

  if (reqPath === "/healthz") {
    sendText(res, 200, "ok");
    return;
  }

  const videoId = decodeURIComponent(reqPath.replace(/^\/+/, "")).split("/")[0];

  if (!/^[A-Za-z0-9_-]{6,}$/.test(videoId)) {
    log("bad video id:", videoId);
    sendText(res, 404, "Not Found");
    return;
  }

  const videoDir = path.join(DOWNLOADS_DIR, videoId);
  const infoPath = path.join(videoDir, "info.txt");

  if (!fs.existsSync(infoPath)) {
    log("no info.txt:", infoPath);
    sendText(res, 404, "Not Found");
    return;
  }

  const info = parseInfoFile(infoPath);

  if (info.STATUS !== "downloaded") {
    log("not downloaded:", videoId, info.STATUS);
    sendText(res, 404, "Not Found");
    return;
  }

  const filePath = findFileFromInfo(videoDir, info);

  if (!filePath) {
    log("file not found:", videoDir);
    sendText(res, 404, "Not Found");
    return;
  }

  const fileName = path.basename(filePath);
  const stat = fs.statSync(filePath);
  log("download:", filePath, `(${stat.size} bytes)`);

  res.writeHead(200, {
    "Content-Type": "application/octet-stream",
    "Content-Disposition": buildContentDisposition(fileName),
    "Content-Length": stat.size,
    "Cache-Control": "no-store",
  });

  fs.createReadStream(filePath).on("error", (err) => {
    log("stream error:", err.message);
    if (!res.headersSent) {
      sendText(res, 500, "Internal Server Error");
    } else {
      res.destroy(err);
    }
  }).pipe(res);
});

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

function shutdown() {
  log("shutting down");
  server.close(() => process.exit(0));
}

server.listen(PORT, HOST, () => {
  log(`listening on ${HOST}:${PORT}`);
});
