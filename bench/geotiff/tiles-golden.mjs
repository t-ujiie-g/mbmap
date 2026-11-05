// GeoTIFF sources drawn by mbmap (mbmap/data's rasterTile in Chromium) vs the pixels they hold:
// GSI's standard map tiles (国土地理院) made a COG in EPSG:3857 come back identical at their zoom,
// the Mt Fuji DEM as Terrarium within 1/256 m, a raster in EPSG:4326 as an independent sampling
// gives it, and a map of the COG source looks as the map of the PNG tiles. Needs `npm --prefix npm run build`.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { decodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";
import { tiffFile } from "../data/tiff-write.mjs";

const R = 6378137;
const WORLD = 2 * Math.PI * R;
const dir = path.join(ROOT, "bench/dist/geotiff");
await mkdir(dir, { recursive: true });

// --- The files ---
// GSI's standard map, z14 tiles 14549-14555 x 6449-6453, one RGB COG with an overview.
const STD = { z: 14, x: [14549, 14555], y: [6449, 6453] };
const cols = STD.x[1] - STD.x[0] + 1;
const rows = STD.y[1] - STD.y[0] + 1;
const [W, H] = [cols * 256, rows * 256];
const rgb = [0, 1, 2].map(() => new Uint8Array(W * H));
const pngs = {};
for (let ty = 0; ty < rows; ty++) {
  for (let tx = 0; tx < cols; tx++) {
    const key = `${STD.z}/${STD.x[0] + tx}/${STD.y[0] + ty}`;
    const png = decodePng(await readFile(path.join(ROOT, "bench/fixtures/gsi-std", `${key}.png`)));
    pngs[key] = png;
    for (let y = 0; y < 256; y++) for (let x = 0; x < 256; x++) for (let c = 0; c < 3; c++) rgb[c][(ty * 256 + y) * W + tx * 256 + x] = png.rgba[(y * 256 + x) * 4 + c];
  }
}
const cell = WORLD / 2 ** STD.z / 256;
const stdGeo = { pixelScale: [cell, cell, 0], tiepoint: [0, 0, 0, -WORLD / 2 + STD.x[0] * 256 * cell, WORLD / 2 - STD.y[0] * 256 * cell, 0] };
const half = (bands, w, h) => bands.map((b) => Uint8Array.from({ length: (w / 2) * (h / 2) }, (_, i) => b[Math.floor(i / (w / 2)) * 2 * w + (i % (w / 2)) * 2]));
await writeFile(path.join(dir, "std.tif"), tiffFile([
  { width: W, height: H, bits: 8, format: 1, values: rgb, tile: [256, 256], compression: 8, predictor: 2, geo: stdGeo, keys: [[1024, 1], [1025, 1], [3072, 3857]] },
  { width: W / 2, height: H / 2, bits: 8, format: 1, values: half(rgb, W, H), tile: [256, 256], compression: 8, subfile: 1 },
], { ifdsFirst: true }));

// The Mt Fuji DEM, z12 tiles 3625-3626 x 1616-1617 (GSI's encoding), as float32 in EPSG:3857.
const DEM = { z: 12, x: 3625, y: 1616 };
const elevation = new Float32Array(512 * 512);
for (let ty = 0; ty < 2; ty++) {
  for (let tx = 0; tx < 2; tx++) {
    const png = decodePng(await readFile(path.join(ROOT, "bench/fixtures/gsi-dem-fuji", `${DEM.z}/${DEM.x + tx}/${DEM.y + ty}.png`)));
    for (let y = 0; y < 256; y++) {
      for (let x = 0; x < 256; x++) {
        const k = (y * 256 + x) * 4;
        const v = png.rgba[k] * 65536 + png.rgba[k + 1] * 256 + png.rgba[k + 2];
        elevation[(ty * 256 + y) * 512 + tx * 256 + x] = v === 2 ** 23 ? NaN : (v < 2 ** 23 ? v : v - 2 ** 24) * 0.01;
      }
    }
  }
}
const demCell = WORLD / 2 ** DEM.z / 256;
await writeFile(path.join(dir, "dem.tif"), tiffFile([
  { width: 512, height: 512, bits: 32, format: 3, values: [Array.from(elevation)], tile: [256, 256], compression: 8, predictor: 3,
    geo: { pixelScale: [demCell, demCell, 0], tiepoint: [0, 0, 0, -WORLD / 2 + DEM.x * 256 * demCell, WORLD / 2 - DEM.y * 256 * demCell, 0] }, keys: [[1024, 1], [1025, 1], [3072, 3857]] },
], { ifdsFirst: true }));

// A surface in EPSG:4326: 0.001 degree pixels west of 139.7, north of 35.72.
const LL = { west: 139.6, north: 35.8, step: 0.001, width: 400, height: 300, at: (lon, lat) => Math.fround(100 * Math.sin((lon - 139.6) * 40) + 50 * Math.cos((lat - 35.6) * 30) + 200) };
const llValues = Array.from({ length: LL.width * LL.height }, (_, i) => LL.at(LL.west + ((i % LL.width) + 0.5) * LL.step, LL.north - (Math.floor(i / LL.width) + 0.5) * LL.step));
await writeFile(path.join(dir, "lonlat.tif"), tiffFile([
  { width: LL.width, height: LL.height, bits: 32, format: 3, values: [llValues], tile: [128, 128], compression: 5, geo: { pixelScale: [LL.step, LL.step, 0], tiepoint: [0, 0, 0, LL.west, LL.north, 0] }, keys: [[1024, 2], [1025, 1], [2048, 4326]], nodata: "-9999" },
]));

// The 4326 surface's gray (or `colors`) at each pixel of tile z/x/y, sampled at the nearest pixel.
function lonlatExpected(z, x, y, range, colors) {
  const out = new Uint8ClampedArray(256 * 256 * 4);
  const px = WORLD / 2 ** z / 256;
  for (let j = 0; j < 256; j++) {
    const my = WORLD / 2 - y * (WORLD / 2 ** z) - (j + 0.5) * px;
    const lat = (Math.atan(Math.sinh(my / R)) * 180) / Math.PI;
    for (let i = 0; i < 256; i++) {
      const lon = ((-WORLD / 2 + x * (WORLD / 2 ** z) + (i + 0.5) * px) / R) * (180 / Math.PI);
      const [sx, sy] = [(lon - LL.west) / LL.step, (LL.north - lat) / LL.step];
      if (sx < 0 || sy < 0 || sx >= LL.width || sy >= LL.height) continue;
      const v = llValues[Math.floor(sy) * LL.width + Math.floor(sx)];
      const o = (j * 256 + i) * 4;
      if (colors) {
        let k = 0;
        while (k < colors.length - 1 && v > colors[k + 1][0]) k++;
        const [va, ca] = colors[k];
        const [vb, cb] = colors[Math.min(k + 1, colors.length - 1)];
        const t = vb > va ? Math.min(1, Math.max(0, (v - va) / (vb - va))) : 0;
        for (let q = 0; q < 4; q++) out[o + q] = Math.round(ca[q] + (cb[q] - ca[q]) * t);
      } else {
        const g = Math.round(Math.min(1, Math.max(0, (v - range[0]) / (range[1] - range[0]))) * 255);
        out[o] = out[o + 1] = out[o + 2] = g;
        out[o + 3] = 255;
      }
    }
  }
  return out;
}

// --- In Chromium ---
const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = {};
let failed = 0;
const record = (group, label, ok, detail = {}) => {
  const r = (results[group] ??= { cases: 0, ok: 0, failed: [] });
  r.cases++;
  if (ok) r.ok++;
  else {
    failed++;
    r.failed.push({ label, ...detail });
  }
};
try {
  const page = await browser.newPage({ viewport: { width: 512, height: 512 } });
  page.on("pageerror", (e) => console.log("pageerror", e.message));
  await page.goto(`${origin}/bench/geotiff/page.html`);
  await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
  const tile = async (file, z, x, y, options = {}) => {
    const b64 = await page.evaluate(async ([url, z, x, y, options]) => {
      const png = await window.data.rasterTile(url, z, x, y, options);
      if (!png) return null;
      let s = "";
      const bytes = new Uint8Array(png);
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return btoa(s);
    }, [`${origin}/bench/dist/geotiff/${file}`, z, x, y, options]);
    return b64 === null ? null : decodePng(Buffer.from(b64, "base64")).rgba;
  };
  const info = await page.evaluate((url) => window.data.rasterInfo(url), `${origin}/bench/dist/geotiff/std.tif`);
  record("info", "std.tif bounds and maxzoom", info.crs === 3857 && info.maxzoom === 14 && Math.abs(info.bounds[0] - (STD.x[0] / 2 ** 14) * 360 + 180) < 1e-9, info);

  // Every z14 tile of the map, identical to its PNG.
  for (const [key, png] of Object.entries(pngs)) {
    const [z, x, y] = key.split("/").map(Number);
    const got = await tile("std.tif", z, x, y);
    let worst = 0;
    for (let i = 0; i < got.length; i++) worst = Math.max(worst, Math.abs(got[i] - (i % 4 === 3 ? 255 : png.rgba[i])));
    record("std z14", key, worst === 0, { worst });
  }
  // Tiles off the file are null; a z13 tile is the overview's pixels.
  record("std", "a tile off the file", (await tile("std.tif", 14, 100, 100)) === null);
  const z13 = await tile("std.tif", 13, Math.floor(STD.x[0] / 2) + 1, Math.floor(STD.y[0] / 2) + 1);
  record("std", "a z13 tile from the overview", z13 !== null && z13.some((v, i) => i % 4 !== 3 && v !== 255));

  // DEM tiles as Terrarium, within its 1/256 m steps.
  for (const [tx, ty] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
    const got = await tile("dem.tif", DEM.z, DEM.x + tx, DEM.y + ty, { dem: true });
    let worst = 0;
    for (let y = 0; y < 256; y++) {
      for (let x = 0; x < 256; x++) {
        const o = (y * 256 + x) * 4;
        const e = got[o] * 256 + got[o + 1] + got[o + 2] / 256 - 32768;
        const want = elevation[(ty * 256 + y) * 512 + tx * 256 + x];
        worst = Math.max(worst, Math.abs(e - (Number.isNaN(want) ? 0 : want)));
      }
    }
    record("dem z12", `${DEM.x + tx}/${DEM.y + ty}`, worst <= 1 / 256, { worst });
  }
  const linear = await tile("dem.tif", DEM.z + 1, DEM.x * 2 + 1, DEM.y * 2 + 1, { dem: true, resampling: "bilinear" });
  record("dem", "a z13 tile, bilinear", linear !== null && linear[3] === 255);

  // The EPSG:4326 surface, gray and through colors, against the sampling above.
  const range = [50, 350];
  const colors = [[100, "#0000ff"], [200, "rgb(0, 255, 0)"], [300, "red"]];
  const rgbaColors = colors.map(([v, c]) => [v, c === "#0000ff" ? [0, 0, 255, 255] : c === "red" ? [255, 0, 0, 255] : [0, 255, 0, 255]]);
  for (const [z, x, y] of [[11, 1818, 806], [12, 3637, 1612], [13, 7274, 3225], [14, 14549, 6450]]) {
    for (const [label, options, want] of [["gray", { range }, lonlatExpected(z, x, y, range)], ["colors", { colors }, lonlatExpected(z, x, y, range, rgbaColors)]]) {
      const got = await tile("lonlat.tif", z, x, y, options);
      let worst = 0;
      let lit = 0;
      for (let i = 0; i < want.length; i++) {
        const g = got ? got[i] : 0;
        if (i % 4 === 3 && want[i] > 0) lit++;
        // A pixel the PNG holds transparent keeps no color.
        if (i % 4 !== 3 && want[i - (i % 4) + 3] === 0) continue;
        worst = Math.max(worst, Math.abs(g - want[i]));
      }
      record("lonlat", `${z}/${x}/${y} ${label}`, worst === 0 && lit > 0, { worst, lit });
    }
  }

  // A map drawing the COG source looks as one drawing the PNG tiles.
  const shot = async (sources) => {
    const p = await browser.newPage({ viewport: { width: 512, height: 512 } });
    await p.goto(`${origin}/bench/geotiff/page.html`);
    await p.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    await p.evaluate((sources) => new Promise((resolve) => {
      const map = new window.mbmap.Map({ container: "map", center: [139.7671, 35.6812], zoom: 14, style: { version: 8, sources, layers: [{ id: "bg", type: "background", paint: { "background-color": "#fff" } }, { id: "r", type: "raster", source: "s" }] } });
      map.once("idle", resolve);
    }), sources);
    const img = decodePng(await p.screenshot());
    await p.close();
    return img.rgba;
  };
  const fromCog = await shot({ s: { type: "geotiff", url: `${origin}/bench/dist/geotiff/std.tif` } });
  const fromPng = await shot({ s: { type: "raster", tiles: [`${origin}/bench/fixtures/gsi-std/{z}/{x}/{y}.png`], tileSize: 256, minzoom: 14, maxzoom: 14 } });
  let worst = 0;
  for (let i = 0; i < fromCog.length; i++) worst = Math.max(worst, Math.abs(fromCog[i] - fromPng[i]));
  record("map", "a geotiff source as the PNG tiles", worst === 0 && fromCog.some((v, i) => i % 4 !== 3 && v < 250), { worst });
} finally {
  await browser.close();
  server.close();
}
for (const [group, r] of Object.entries(results)) {
  console.log(`${group}: ${r.ok} of ${r.cases} ok`);
  for (const f of r.failed.slice(0, 5)) console.log("  FAIL", JSON.stringify(f).slice(0, 300));
}
await writeFile(path.join(ROOT, "bench/results/geotiff-tiles.json"), JSON.stringify({ results, failed }, null, 2) + "\n");
console.log(failed === 0 ? "all ok" : `${failed} failed`);
if (failed > 0) process.exit(1);
