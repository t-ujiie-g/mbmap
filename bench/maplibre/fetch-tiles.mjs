// Downloads the GSI bench tile sets and verifies each against its
// bench/fixtures/<set>.manifest.json (see bench/fixtures/README.md);
// --update rewrites the manifests.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";

export const TILES = { z: 14, x: [14549, 14555], y: [6449, 6453] };
// The vector tiles, standard map images and DEM of TILES, and a DEM of Mt Fuji for relief that shows.
const SETS = [
  {
    name: "gsi-bvmap", ext: "pbf", ...TILES,
    url: "https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf",
    attribution: "国土地理院ベクトルタイル提供実験 (GSI Japan)",
  },
  {
    name: "gsi-dem", ext: "png", ...TILES,
    url: "https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png",
    attribution: "国土地理院 標高タイル (GSI Japan)",
  },
  {
    name: "gsi-std", ext: "png", ...TILES,
    url: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png",
    attribution: "国土地理院 標準地図 (GSI Japan)",
  },
  {
    name: "gsi-dem-fuji", ext: "png", z: 12, x: [3625, 3628], y: [1616, 1619],
    url: "https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png",
    attribution: "国土地理院 標高タイル (GSI Japan)",
  },
];
const update = process.argv.includes("--update");
const hash = (b) => createHash("sha256").update(b).digest("hex");

let failed = false;
for (const set of SETS) {
  const dir = path.join(ROOT, "bench/fixtures", set.name);
  const manifestPath = path.join(ROOT, `bench/fixtures/${set.name}.manifest.json`);
  let manifest = null;
  try { manifest = JSON.parse(await readFile(manifestPath, "utf8")); } catch {}
  const jobs = [];
  for (let x = set.x[0]; x <= set.x[1]; x++)
    for (let y = set.y[0]; y <= set.y[1]; y++) jobs.push({ z: set.z, x, y });
  const entries = {};
  let mismatches = 0;
  const worker = async () => {
    for (let job; (job = jobs.shift()); ) {
      const key = `${job.z}/${job.x}/${job.y}`;
      const file = path.join(dir, `${key}.${set.ext}`);
      let buf = await readFile(file).catch(() => null);
      const expected = manifest?.tiles?.[key]?.sha256;
      if (!buf || (expected && hash(buf) !== expected)) {
        const res = await fetch(set.url.replace("{z}", job.z).replace("{x}", job.x).replace("{y}", job.y));
        if (!res.ok) throw new Error(`${set.name} ${key}: HTTP ${res.status}`);
        buf = Buffer.from(await res.arrayBuffer());
        await mkdir(path.dirname(file), { recursive: true });
        await writeFile(file, buf);
      }
      const sha256 = hash(buf);
      if (expected && expected !== sha256) {
        mismatches++;
        console.warn(`${set.name} ${key}: upstream content changed (sha256 ${sha256})`);
      }
      entries[key] = { bytes: buf.length, sha256 };
    }
  };
  await Promise.all([worker(), worker(), worker(), worker()]);
  if (!manifest || update) {
    const tiles = Object.fromEntries(Object.entries(entries).sort());
    const total = Object.values(tiles).reduce((a, t) => a + t.bytes, 0);
    await writeFile(manifestPath, JSON.stringify({
      source: set.url,
      attribution: set.attribution,
      fetched: new Date().toISOString().slice(0, 10),
      totalBytes: total,
      tiles,
    }, null, 2) + "\n");
    console.log(`${set.name}: wrote manifest, ${Object.keys(tiles).length} tiles, ${total} bytes`);
  } else if (mismatches) {
    console.error(`${set.name}: ${mismatches} tiles differ from the manifest; results are not comparable. Re-run with --update to accept.`);
    failed = true;
  } else {
    console.log(`${set.name}: fixtures OK, ${Object.keys(entries).length} tiles`);
  }
}
if (failed) process.exitCode = 1;
