// Runs the backend comparison in Node and writes bench/results/backend-node.json.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { gzipSync, brotliCompressSync } from "node:zlib";
import path from "node:path";
import { loadModules, BUILD } from "./load.mjs";
import { runSuite, runAllocSuite } from "./harness.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

const sizes = {};
for (const [key, rel] of Object.entries(BUILD)) {
  const buf = await readFile(path.join(root, rel));
  sizes[key] = { raw: buf.length, gzip: gzipSync(buf, { level: 9 }).length, brotli: brotliCompressSync(buf).length };
}

const { modules, load } = await loadModules({
  fetchBytes: (rel) => readFile(path.join(root, rel)),
  importJs: (rel) => import(pathToFileURL(path.join(root, rel)).href),
});
const result = { ...runSuite(modules), alloc: runAllocSuite(modules) };
const out = { env: { runtime: `node ${process.version}`, v8: process.versions.v8, platform: `${process.platform}-${process.arch}` }, sizes, load, ...result };
await mkdir(path.join(root, "bench/results"), { recursive: true });
await writeFile(path.join(root, "bench/results/backend-node.json"), JSON.stringify(out, null, 2) + "\n");
console.table(result.rows.map((r) => ({ name: r.name, ok: r.correct, in: r.in?.median.toFixed(2), decode: r.decode?.median.toFixed(2), out: r.out?.median.toFixed(2), view: r.outView?.median.toFixed(3), total: r.total?.median.toFixed(2) })));
console.table(result.alloc.rows.map((r) => ({ name: r.name, ok: r.correct, ms: r.time.median.toFixed(2) })));
console.log(sizes, load);
