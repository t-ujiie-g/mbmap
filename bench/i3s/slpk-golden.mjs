// mbmap/3d's SLPK reader (npm/src/i3s/slpk.ts) vs the files it was packed from and @loaders.gl/i3s 4.5.4's
// parseSLPKArchive: SLPKs written here from the synthetic layer (and Esri's San Francisco sample when its
// fixtures are there), stored, deflated, zip64, with and without the hash table, read from bytes, a Blob and
// a local server with and without range requests; requests and bytes counted; hostile copies refused.
// Usage: node i3s/slpk-golden.mjs; writes bench/results/i3s-slpk.json.
import { existsSync } from "node:fs";
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { gzipSync } from "node:zlib";
import { parseSLPKArchive } from "@loaders.gl/i3s";
import { DataViewReadableFile } from "@loaders.gl/zip";
import { openSlpk } from "../../npm/src/i3s/slpk.ts";
import { entryOf, resources, writeSlpk } from "./slpk-write.mjs";
import { ROOT } from "../lib/root.mjs";

const FILLER_NODES = 20_000;
const LAYERS = [
  ["synthetic", [path.join(ROOT, "bench/npm/pages/i3s/set/layers/0")]],
  ["i3s-sf", [path.join(ROOT, "bench/fixtures/i3s-sf"), path.join(ROOT, "bench/fixtures/i3s-sf-pages")]],
];

/** A server of `files` on 127.0.0.1: `/ranges/<name>` answers Range requests (suffix ones too), `/whole/<name>` always the whole file; requests and bytes counted per path. */
function serve(files) {
  const log = new Map();
  const server = http.createServer((req, res) => {
    const [, mode, name] = req.url.split("/");
    const file = files.get(name);
    if (!file) return res.writeHead(404).end();
    const entry = log.get(req.url) ?? { requests: 0, bytes: 0 };
    log.set(req.url, entry);
    entry.requests++;
    const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? "");
    if (mode !== "ranges" || !m) {
      entry.bytes += file.length;
      return res.writeHead(200, { "content-length": file.length }).end(file);
    }
    const [s, e] = m[1] === "" ? [Math.max(0, file.length - Number(m[2])), file.length - 1] : [Number(m[1]), Math.min(file.length - 1, Number(m[2] || file.length - 1))];
    const body = file.subarray(s, e + 1);
    entry.bytes += body.length;
    res.writeHead(206, { "content-range": `bytes ${s}-${e}/${file.length}`, "content-length": body.length }).end(body);
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve({ server, log, url: `http://127.0.0.1:${server.address().port}` })));
}

const same = (a, b) => a !== undefined && b !== undefined && Buffer.compare(Buffer.from(a), Buffer.from(b)) === 0;
const VARIANTS = [
  ["stored, hash table", { hash: true }],
  ["stored, no hash table", { hash: false }],
  ["zip64, hash table", { zip64: true, hash: true }],
  // loaders.gl reads entries as stored (SLPKs must be), so deflated ones are compared with the files only.
  ["deflated, no hash table", { hash: false, deflate: true }],
];

const results = { layers: {}, hostile: [] };
let differ = 0;
const files = new Map();
const layers = [];
for (const [name, dirs] of LAYERS) {
  if (!dirs.every(existsSync)) {
    console.log(`${name}: fixtures missing, skipped (npm run fixtures)`);
    continue;
  }
  const res = await resources(dirs);
  const entries = [...res].map(([rest, bytes]) => entryOf(rest, bytes));
  // The other nodes of a real layer (empty geometries), so the directory is far larger than the first read.
  const empty = new Uint8Array(gzipSync(new Uint8Array(0)));
  for (let i = 0; i < FILLER_NODES; i++) entries.push([`nodes/${1_000_000 + i}/geometries/0.bin.gz`, empty]);
  for (const [variant, options] of VARIANTS) files.set(`${name}-${VARIANTS.findIndex(([v]) => v === variant)}.slpk`, writeSlpk(entries, options));
  layers.push([name, res]);
}
const { server, log, url } = await serve(files);

for (const [name, res] of layers) {
  const row = (results.layers[name] = { resources: res.size, variants: {} });
  for (const [k, [variant]] of VARIANTS.entries()) {
    const file = `${name}-${k}.slpk`;
    const bytes = files.get(file);
    const v = (row.variants[variant] = { bytes: bytes.length, differ: 0 });
    const loaders = await parseSLPKArchive(new DataViewReadableFile(new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)));
    const sources = [
      ["bytes", () => openSlpk(bytes)],
      ["Blob", () => openSlpk(new Blob([bytes]))],
      ["ranges", () => openSlpk(`${url}/ranges/${file}`)],
      ["whole", () => openSlpk(`${url}/whole/${file}`)],
    ];
    for (const [how, open] of sources) {
      const slpk = await open();
      v[how] = { mode: slpk.mode, index: slpk.index };
      for (const [rest, want] of res) {
        const got = await slpk.get(rest);
        const theirs = variant.startsWith("deflated") ? want : new Uint8Array(await loaders.getFile(rest === "layer" ? "" : rest, "http"));
        if (!same(got, want) || !same(got, theirs)) {
          v.differ++;
          if (v.differ <= 3) console.log(`${name} ${variant} ${how}: ${rest} ${same(got, want) ? "differs from loaders.gl's" : "differs from the file"}`);
        }
      }
      if ((await slpk.get("nodes/999999/geometries/0")) !== undefined) v.differ++;
    }
    differ += v.differ;
  }
  // What the range path reads to open the archive and fetch every node page, then one node's resources.
  const pages = [...res.keys()].filter((r) => r.startsWith("nodepages/"));
  const node = [...res.keys()].filter((r) => r.startsWith(`nodes/${[...res.keys()].find((r) => r.startsWith("nodes/")).split("/")[1]}/`));
  const count = (prefix) => [...log].filter(([u]) => u.startsWith(prefix)).reduce((s, [, e]) => ({ requests: s.requests + e.requests, bytes: s.bytes + e.bytes }), { requests: 0, bytes: 0 });
  for (const [what, index] of [["hash table", 0], ["central directory", 1]]) {
    const f = `${name}-${index}.slpk`;
    const before = count(`/ranges/${f}`);
    const slpk = await openSlpk(`${url}/ranges/${f}`);
    const opened = count(`/ranges/${f}`);
    await Promise.all(["layer", "nodepages/0"].map((p) => slpk.get(p)));
    const started = count(`/ranges/${f}`);
    await Promise.all(pages.map((p) => slpk.get(p)));
    const paged = count(`/ranges/${f}`);
    await Promise.all(node.map((p) => slpk.get(p)));
    const done = count(`/ranges/${f}`);
    const d = (a, b) => ({ requests: a.requests - b.requests, bytes: a.bytes - b.bytes });
    const r = (row[`reads (${what})`] = {
      file: files.get(f).length,
      index: slpk.index,
      open: d(opened, before),
      layerAndFirstPage: d(started, opened),
      nodePages: { count: pages.length, ...d(paged, started) },
      node: { resources: node.length, ...d(done, paged) },
    });
    const t = (x) => `${x.requests} requests, ${x.bytes} bytes`;
    console.log(`${name} by ranges (${slpk.index}): a file of ${r.file} bytes; open ${t(r.open)}; layer and node page 0 ${t(r.layerAndFirstPage)}; the other node pages (${pages.length} in all) ${t(r.nodePages)}; one node's ${node.length} resources ${t(r.node)}`);
  }
  console.log(`${name}: ${res.size} resources x ${VARIANTS.length} archives x 4 sources, ${Object.values(row.variants).reduce((s, v) => s + v.differ, 0)} differ`);
}

// Hostile copies of the synthetic stored archive (with and without its hash table).
const base = files.get("synthetic-1.slpk");
const hashed = files.get("synthetic-0.slpk");
const dv = (b) => new DataView(b.buffer, b.byteOffset, b.byteLength);
const edit = (b, f) => {
  const c = b.slice();
  f(dv(c), c);
  return c;
};
const eocd = (b) => b.length - 22;
const dirAt = (b) => dv(b).getUint32(eocd(b) + 16, true);
const hashData = (b) => Buffer.from(b).indexOf("@specialIndexFileHASH128@") + 25;
const HOSTILE = [
  ["truncated", base.subarray(0, base.length - 30)],
  ["half a file", base.subarray(0, base.length >> 1)],
  ["no end record", edit(base, (v) => v.setUint32(eocd(base), 0, true))],
  ["directory past the end", edit(base, (v) => v.setUint32(eocd(base) + 16, base.length, true))],
  ["absurd entry count", edit(base, (v) => v.setUint16(eocd(base) + 10, 0xfffe, true))],
  ["directory record of another signature", edit(base, (v) => v.setUint32(dirAt(base), 0x12345678, true))],
  ["entries overlapping (a zip bomb's shared data)", edit(base, (v) => v.setUint32(dirAt(base) + 46 + 20 + 42, 0, true))],
  ["entry offset past the directory", edit(base, (v) => v.setUint32(dirAt(base) + 42, dirAt(base) - 4, true))],
  ["entry sizes past the cap", edit(base, (v) => [20, 24].forEach((o) => v.setUint32(dirAt(base) + o, 0xfffffff0, true)))],
  ["local header of another name", edit(base, (_, c) => (c[30] ^= 1))],
  ["hash table offsets past the directory", edit(hashed, (v) => { for (let at = hashData(hashed); at < dirAt(hashed) - 24; at += 24) v.setUint32(at + 16, hashed.length, true); })],
  ["gzip bomb entry", writeSlpk([["3dSceneLayer.json.gz", new Uint8Array(gzipSync(Buffer.alloc(300 << 20)))]])],
];
for (const [what, bytes] of HOSTILE) {
  let refused = false;
  try {
    const s = await openSlpk(bytes);
    for (const rest of layers[0][1].keys()) await s.get(rest);
  } catch {
    refused = true;
  }
  results.hostile.push({ what, refused });
}
server.close();
const accepted = results.hostile.filter((h) => !h.refused);
console.log(`hostile: ${results.hostile.length - accepted.length} of ${results.hostile.length} refused${accepted.length ? ` (accepted: ${accepted.map((h) => h.what).join(", ")})` : ""}`);
console.log(`differ: ${differ}`);
results.differ = differ;
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/i3s-slpk.json"), JSON.stringify({ date: new Date().toISOString(), node: process.version, ...results }, null, 2) + "\n");
if (differ || accepted.length) process.exitCode = 1;
