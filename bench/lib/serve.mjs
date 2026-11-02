// Minimal static file server rooted at the repository, for browser benches.
import http from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ROOT } from "./root.mjs";

const TYPES = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript",
  ".json": "application/json", ".wasm": "application/wasm", ".css": "text/css",
  ".pbf": "application/x-protobuf", ".map": "application/json",
};

// Returns the file under ROOT for a request path, or null if the path escapes
// ROOT or touches a dotfile (.git, .env, …).
export function resolveRequestPath(pathname) {
  let decoded;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  if (decoded.includes("\0")) return null;
  const file = path.resolve(ROOT, "." + path.posix.normalize("/" + decoded));
  const rel = path.relative(ROOT, file);
  if (rel === "" || rel.startsWith("..") || path.isAbsolute(rel)) return null;
  if (rel.split(path.sep).some((seg) => seg.startsWith("."))) return null;
  return file;
}

// The byte range a `Range: bytes=a-b` header asks of a file `size` bytes long:
// [start, end] inclusive, null for none, or "bad" for one it cannot serve.
export function byteRange(header, size) {
  if (!header) return null;
  const m = /^bytes=(\d+)-(\d*)$/.exec(header);
  if (!m) return "bad";
  const start = Number(m[1]);
  const end = m[2] === "" ? size - 1 : Math.min(Number(m[2]), size - 1);
  return start <= end ? [start, end] : "bad";
}

export function serve(port = 0) {
  const server = http.createServer(async (req, res) => {
    let file = resolveRequestPath(new URL(req.url, "http://x").pathname);
    if (!file) { res.writeHead(403).end(); return; }
    try {
      if ((await stat(file)).isDirectory()) file = path.join(file, "index.html");
      if (!(await stat(file)).isFile()) throw new Error("not a file");
      const body = await readFile(file);
      // The cross-origin isolation headers enable high-resolution timers
      // (performance.now) in browsers.
      const headers = {
        "content-type": TYPES[path.extname(file)] ?? "application/octet-stream",
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
        "cross-origin-opener-policy": "same-origin",
        "cross-origin-embedder-policy": "require-corp",
        "accept-ranges": "bytes",
      };
      // Single ranges, for PMTiles archives.
      const range = byteRange(req.headers.range, body.length);
      if (range === "bad") {
        res.writeHead(416, { "content-range": `bytes */${body.length}` }).end();
      } else if (range) {
        res.writeHead(206, { ...headers, "content-range": `bytes ${range[0]}-${range[1]}/${body.length}` });
        res.end(body.subarray(range[0], range[1] + 1));
      } else {
        res.writeHead(200, headers);
        res.end(body);
      }
    } catch {
      res.writeHead(404).end();
    }
  });
  return new Promise((resolve) => server.listen(port, "127.0.0.1", () => resolve({ server, origin: `http://127.0.0.1:${server.address().port}` })));
}

// `node bench/lib/serve.mjs [port]` serves the repository for examples.
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const { origin } = await serve(Number(process.argv[2] ?? 8080));
  console.log(`serving ${ROOT} at ${origin}/ (examples: ${origin}/examples/)`);
}
