#!/usr/bin/env node
// Static server for the production Elm build (frontends/elm-spa/public, incl. dist/elm.js from
// `check.sh build`), with SPA fallback to index.html -- what `elm-spa server` does, without needing
// the Elm toolchain to keep running. Local testing only: binds to loopback.
// Usage: node serve.cjs [port=1234] [public-dir]
const http = require("http");
const fs = require("fs");
const path = require("path");

const root = path.resolve(process.argv[3] || path.join(__dirname, "../../../frontends/elm-spa/public"));
const port = Number(process.argv[2] || 1234);
const types = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".woff2": "font/woff2",
};

/** `file` is `root` itself or inside it (a separator-aware check: `/x/public-private` is not inside `/x/public`). */
const inside = file => file === root || file.startsWith(root + path.sep);

http
  .createServer((req, res) => {
    let urlPath;
    try {
      urlPath = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    } catch {
      res.writeHead(400);
      return res.end("bad request");
    }
    let file = path.resolve(path.join(root, urlPath));
    if (!inside(file)) {
      res.writeHead(403);
      return res.end("forbidden");
    }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, "index.html");
    res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
    fs.createReadStream(file).pipe(res);
  })
  .listen(port, "127.0.0.1", () => console.log(`serving ${root} on http://localhost:${port}`));
