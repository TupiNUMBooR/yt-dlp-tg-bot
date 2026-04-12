const http = require("http");
const fs = require("fs");
const path = require("path");

const HOST = "0.0.0.0";
const PORT = Number(process.env.PORT || 3000);
const DOWNLOADS_DIR = "/app/done";

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
  return `attachment; filename="${fileName.replace(/"/g, "")}"`;
}

const server = http.createServer((req, res) => {
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

  if (!/^[a-f0-9]{6}$/.test(jobId)) {
    sendText(res, 404, "Not Found");
    return;
  }

  const jobDir = path.join(DOWNLOADS_DIR, jobId);
  const info = parseInfoFile(path.join(jobDir, "info.txt"));

  if (info.STATUS !== "done" || !info.FILE_NAME) {
    sendText(res, 404, "Not Found");
    return;
  }

  const filePath = path.join(jobDir, info.FILE_NAME);

  res.writeHead(200, {
    "Content-Type": "application/octet-stream",
    "Content-Disposition": buildContentDisposition(info.FILE_NAME),
    "Cache-Control": "no-store",
  });

  fs.createReadStream(filePath).pipe(res);
});

server.listen(PORT, HOST, () => {
  console.log(`Listening on ${HOST}:${PORT}`);
});
