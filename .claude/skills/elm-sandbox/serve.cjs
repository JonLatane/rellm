#!/usr/bin/env node
// Static server for the production Elm build (frontends/elm-spa/public, incl. dist/elm.js from
// `elm-spa build`), with SPA fallback to index.html -- what `elm-spa server` does, without needing
// the Elm toolchain to keep running. Usage: node serve.cjs [port=1234] [public-dir]
const http = require("http");
const fs = require("fs");
const path = require("path");

const root = path.resolve(process.argv[3] || path.join(__dirname, "../../../frontends/elm-spa/public"));
const port = Number(process.argv[2] || 1234);
const types = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".woff2": "font/woff2",
};

http
  .createServer((req, res) => {
    const urlPath = decodeURIComponent(new URL(req.url, "http://x").pathname);
    let file = path.join(root, urlPath);
    if (!file.startsWith(root)) { res.writeHead(403); return res.end(); }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, "index.html");
    res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
    fs.createReadStream(file).pipe(res);
  })
  .listen(port, () => console.log(`serving ${root} on http://localhost:${port}`));
