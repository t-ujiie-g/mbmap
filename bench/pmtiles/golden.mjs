// PMTiles: archives written from the bench fixtures (a root directory only,
// leaf directories, gzip-compressed tiles, raster tiles) are read back in Node
// by the official pmtiles 4.5.0 reader and by mbmap's (worker/js/pmtiles.mjs),
// which must both give every tile's bytes; then in Chromium mbmap draws from
// the archives what MapLibre draws from the files (bench/query's page): the
// same query results and the same raster pixels.
// Writes bench/results/pmtiles-golden.json. Needs `npm --prefix npm run build`.
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { PMTiles } from "pmtiles";
import { Archive } from "../../worker/js/pmtiles.mjs";
import { writeArchive } from "../lib/pmtiles-writer.mjs";
import { decodePng } from "../lib/png.mjs";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";

async function fixtureTiles(set, ext) {
  const out = [];
  const dir = path.join(ROOT, "bench/fixtures", set, "14");
  for (const x of await readdir(dir)) for (const f of await readdir(path.join(dir, x))) {
    out.push({ z: 14, x: Number(x), y: Number(path.basename(f, `.${ext}`)), bytes: await readFile(path.join(dir, x, f)) });
  }
  return out;
}

const vector = await fixtureTiles("gsi-bvmap", "pbf");
const raster = await fixtureTiles("gsi-std", "png");
const archives = {
  "vector-root": [vector, { tileType: 1 }],
  "vector-leaves": [vector, { tileType: 1, leafSize: 8 }],
  "vector-gzip": [vector, { tileType: 1, gzipTiles: true, leafSize: 8 }],
  "raster": [raster, { tileType: 2 }],
};
await mkdir(path.join(ROOT, "bench/dist"), { recursive: true });
const results = [];
let failed = 0;
for (const [name, [tiles, options]] of Object.entries(archives)) {
  const bytes = writeArchive(tiles, options);
  await writeFile(path.join(ROOT, `bench/dist/${name}.pmtiles`), bytes);
  const range = async (offset, length) => new Uint8Array(bytes.subarray(offset, offset + length));
  const official = new PMTiles({ getKey: () => name, getBytes: async (offset, length) => ({ data: (await range(offset, length)).slice().buffer }) });
  const ours = new Archive(name, (_, offset, length) => range(offset, length));
  let same = 0;
  for (const t of [...tiles, { z: 14, x: 0, y: 0, bytes: null }, { z: 13, x: 7275, y: 3225, bytes: null }]) {
    const a = await official.getZxy(t.z, t.x, t.y);
    const b = await ours.tile(t.z, t.x, t.y);
    const want = t.bytes ? Buffer.from(t.bytes) : null;
    const eq = (v) => (v === null || v === undefined ? want === null : want !== null && Buffer.compare(Buffer.from(v), want) === 0);
    if (eq(a?.data ?? null) && eq(b)) same++;
  }
  const ok = same === tiles.length + 2;
  if (!ok) failed++;
  results.push({ check: "node", archive: name, bytes: bytes.length, tiles: tiles.length + 2, same, ok });
}

// In Chromium: mbmap from the archives, MapLibre from the files.
const tokyo = [139.7671, 35.6812];
const base = JSON.parse(await readFile(path.join(ROOT, "bench/maplibre/style.json"), "utf8"));
const styles = {
  "vector-ml": base,
  "vector": { ...base, sources: { gsi: { type: "vector", url: "pmtiles://{origin}/bench/dist/vector-gzip.pmtiles" } } },
  "raster-ml": { version: 8, sources: { std: { type: "raster", tiles: ["{origin}/bench/fixtures/gsi-std/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 14, maxzoom: 14 } }, layers: [{ id: "std", type: "raster", source: "std" }] },
  "raster": { version: 8, sources: { std: { type: "raster", url: "pmtiles://{origin}/bench/dist/raster.pmtiles", tileSize: 256 } }, layers: [{ id: "std", type: "raster", source: "std" }] },
};
for (const [name, s] of Object.entries(styles)) await writeFile(path.join(ROOT, `bench/dist/pmtiles-${name}.json`), JSON.stringify(s));
const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
try {
  for (const kind of ["vector", "raster"]) {
    const page = await browser.newPage({ viewport: { width: 800, height: 1200 } });
    page.on("pageerror", (e) => console.log(kind, "pageerror", e.message));
    const camera = { center: tokyo, zoom: 15, bearing: 0, pitch: 0 };
    await page.goto(`${origin}/bench/query/index.html?style=/bench/dist/pmtiles-${kind}.json&mlstyle=/bench/dist/pmtiles-${kind}-ml.json&camera=${encodeURIComponent(JSON.stringify(camera))}`);
    await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    if (kind === "raster") {
      const shot = (y) => page.screenshot({ clip: { x: 0, y, width: 800, height: 600 } }).then((b) => decodePng(b));
      const [a, b] = [await shot(0), await shot(600)];
      let max = 0;
      for (let i = 0; i < a.rgba.length; i++) max = Math.max(max, Math.abs(a.rgba[i] - b.rgba[i]));
      const ok = max <= 1;
      if (!ok) failed++;
      results.push({ check: "chromium", archive: "raster", maxPixelDifference: max, ok });
    } else {
      let same = 0;
      let features = 0;
      const asks = [[400, 300], [200, 150], [[100, 100], [700, 500]], null];
      for (const g of asks) {
        const r = await page.evaluate((geom) => window.__query("rendered", geom), g);
        const key = (xs) => JSON.stringify(xs.map((f) => ({ ...f, source: undefined })));
        features += r.mbmap.length;
        if (key(r.mbmap) === key(r.maplibre)) same++;
      }
      const ok = same === asks.length && features > 0;
      if (!ok) failed++;
      results.push({ check: "chromium", archive: "vector-gzip", queries: asks.length, features, same, ok });
    }
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/pmtiles-golden.json"), JSON.stringify({ env: { pmtiles: "4.5.0", maplibre: "6.16.0", browser: "chromium" }, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
if (failed) process.exit(1);
