const http = require("http");
const fs = require("fs");
const path = require("path");

const HOST = "0.0.0.0";
const PORT = Number(process.env.PORT || 3000);
const DOWNLOADS_DIR = "/app/published";

function log(...args) {
  console.log("[ms-server]", ...args);
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

  const jobId = reqPath.replace(/^\/+/, "");

  if (!/^[a-f0-9]{6,}$/.test(jobId)) {
    log("bad job id:", jobId);
    sendText(res, 404, "Not Found");
    return;
  }

  const jobDir = path.join(DOWNLOADS_DIR, jobId);
  const infoPath = path.join(jobDir, "info.txt");

  if (!fs.existsSync(infoPath)) {
    log("no info.txt:", infoPath);
    sendText(res, 404, "Not Found");
    return;
  }

  const info = parseInfoFile(infoPath);

  if (!info.FILE_NAME) {
    log("FILE_NAME empty:", infoPath);
    sendText(res, 404, "Not Found");
    return;
  }

  const filePath = path.join(jobDir, info.FILE_NAME);

  if (!fs.existsSync(filePath)) {
    log("file not found:", filePath);
    sendText(res, 404, "Not Found");
    return;
  }

  const stat = fs.statSync(filePath);
  log("download:", filePath, `(${stat.size} bytes)`);

  res.writeHead(200, {
    "Content-Type": "application/octet-stream",
    "Content-Disposition": buildContentDisposition(info.FILE_NAME),
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
  log("Shutting down...");

  server.close(() => {
    log("Server closed");
    process.exit(0);
  });
}

server.listen(PORT, HOST, () => {
  log(`Listening on ${HOST}:${PORT}`);
});
