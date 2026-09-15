#!/usr/bin/env node
/* Tiny static server for local play: `npm run serve`, then open the URL.
   The game also runs straight off the filesystem, this is just convenient.  */
"use strict";
const http = require("http"), fs = require("fs"), path = require("path");
const ROOT = path.join(__dirname, "..");
const PORT = Number(process.env.PORT || 8080);
const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png",
  ".wasm": "application/wasm", ".pck": "application/octet-stream" };

http.createServer((req, res) => {
  const rel = decodeURIComponent(req.url.split("?")[0]);
  let file = path.normalize(path.join(ROOT, rel));
  if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end("forbidden"); }
  if (file.endsWith(path.sep) || rel === "/") file = path.join(file, "index.html");
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end("not found"); }
    res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
    res.end(data);
  });
}).listen(PORT, () => console.log(`Tactics Core → http://localhost:${PORT}/`));
