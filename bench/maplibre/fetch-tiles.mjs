// Downloads the GSI bench tiles and verifies them against gsi-bvmap.manifest.json
// (see bench/fixtures/README.md); --update rewrites the manifest.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";

export const TILES = { z: 14, x: [14549, 14555], y: [6449, 6453] };
const URL_TEMPLATE = "https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf";
const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap");
const manifestPath = path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json");
const update = process.argv.includes("--update");

let manifest = null;
try { manifest = JSON.parse(await readFile(manifestPath, "utf8")); } catch {}

const jobs = [];
for (let x = TILES.x[0]; x <= TILES.x[1]; x++)
  for (let y = TILES.y[0]; y <= TILES.y[1]; y++) jobs.push({ z: TILES.z, x, y });

const entries = {};
let mismatches = 0;
async function worker() {
  for (let job; (job = jobs.shift()); ) {
    const key = `${job.z}/${job.x}/${job.y}`;
    const file = path.join(dir, `${key}.pbf`);
    let buf = await readFile(file).catch(() => null);
    const expected = manifest?.tiles?.[key]?.sha256;
    const hash = (b) => createHash("sha256").update(b).digest("hex");
    if (!buf || (expected && hash(buf) !== expected)) {
      const res = await fetch(URL_TEMPLATE.replace("{z}", job.z).replace("{x}", job.x).replace("{y}", job.y));
      if (!res.ok) throw new Error(`${key}: HTTP ${res.status}`);
      buf = Buffer.from(await res.arrayBuffer());
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, buf);
    }
    const sha256 = hash(buf);
    if (expected && expected !== sha256) {
      mismatches++;
      console.warn(`${key}: upstream content changed (sha256 ${sha256})`);
    }
    entries[key] = { bytes: buf.length, sha256 };
  }
}
await Promise.all([worker(), worker(), worker(), worker()]);

if (!manifest || update) {
  const tiles = Object.fromEntries(Object.entries(entries).sort());
  const total = Object.values(tiles).reduce((a, t) => a + t.bytes, 0);
  await writeFile(manifestPath, JSON.stringify({
    source: URL_TEMPLATE,
    attribution: "国土地理院ベクトルタイル提供実験 (GSI Japan)",
    fetched: new Date().toISOString().slice(0, 10),
    totalBytes: total,
    tiles,
  }, null, 2) + "\n");
  console.log(`wrote manifest: ${Object.keys(tiles).length} tiles, ${total} bytes`);
} else if (mismatches) {
  console.error(`${mismatches} tiles differ from the manifest; results are not comparable. Re-run with --update to accept.`);
  process.exitCode = 1;
} else {
  console.log(`fixtures OK: ${Object.keys(entries).length} tiles`);
}
