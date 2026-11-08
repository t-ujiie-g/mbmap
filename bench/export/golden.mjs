// `Map.toBlob` in Chromium: parts joined vs drawn whole, pixelRatio 1 vs the canvas, 2x raster vs
// MapLibre GL JS 6.16.0 on a 2x screen. Writes bench/results/export-golden.json; needs the npm
// build and the gsi-bvmap, gsi-std, gsi-std-world and gsi-dem-fuji fixtures.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { fujiTerrainStyle } from "../lib/fuji-terrain.mjs";
import { decodePng } from "../lib/png.mjs";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";

const base = JSON.parse(await readFile(path.join(ROOT, "bench/maplibre/style.json"), "utf8"));
const basic = JSON.parse(await readFile(path.join(ROOT, "bench/pages/basic/style.json"), "utf8"));
base.layers.push(...basic.layers.filter((l) => l.type === "symbol"));
const terrain = await fujiTerrainStyle();
terrain.sky = { "sky-color": "#88C6FC", "horizon-color": "#ffffff", "fog-color": "#ffffff" };
const raster = {
  version: 8,
  sources: { std: { type: "raster", tiles: ["{origin}/bench/fixtures/gsi-std/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 14, maxzoom: 14 } },
  layers: [{ id: "bg", type: "background", paint: { "background-color": "#ffffff" } }, { id: "std", type: "raster", source: "std" }],
};
const globe = {
  version: 8,
  projection: { type: "globe" },
  sky: { "atmosphere-blend": 0.8 },
  sources: { world: { type: "raster", tiles: ["{origin}/bench/fixtures/gsi-std-world/{z}/{x}/{y}.png"], tileSize: 256, maxzoom: 3 } },
  layers: [{ id: "world", type: "raster", source: "world" }],
};
const styles = { vector: base, terrain, raster, globe };
for (const [name, style] of Object.entries(styles)) await writeFile(path.join(ROOT, `bench/dist/export-${name}.json`), JSON.stringify(style));

// Each view: its style and camera, the pixel ratio, and the part size of the split image.
const views = {
  labels: { style: "vector", camera: { center: [139.7671, 35.6812], zoom: 15, bearing: 20, pitch: 50 }, ratio: 2, maxSize: 300 },
  terrain: { style: "terrain", camera: { center: [138.76, 35.33], zoom: 13, bearing: -40, pitch: 75 }, ratio: 2, maxSize: 256 },
  globe: { style: "globe", camera: { center: [139.7671, 35.6812], zoom: 2.2, bearing: 30, pitch: 40 }, ratio: 2, maxSize: 300 },
  odd: { style: "vector", camera: { center: [139.7671, 35.6812], zoom: 15.4, bearing: -60, pitch: 0 }, ratio: 1.5, maxSize: 333 },
};
// Per-channel differences allowed. Parts are drawn through one more matrix,
// whose rounding moves a few antialiased edge pixels by a level or so; MapLibre
// on a 2x screen against mbmap's 2x image as bench/raster/golden.mjs.
const LIMITS = { split: { mean: 0.01, p99: 0 }, maplibre: { mean: 0.05, p99: 1 } };

/** The images `options` list, made in the page, as decoded PNGs. */
async function images(page, list) {
  const out = await page.evaluate(async (list) => {
    const read = (blob) => new Promise((r) => {
      const f = new FileReader();
      f.onload = () => r(f.result.split(",")[1]);
      f.readAsDataURL(blob);
    });
    const res = [];
    for (const o of list) res.push(await read(await window.__mb.toBlob(o)));
    return res;
  }, list);
  return out.map((b) => decodePng(Buffer.from(b, "base64")));
}

/** `image` over the page's white, as the screen shows the clear space around the globe. */
function overWhite(image) {
  const rgba = Uint8Array.from(image.rgba);
  for (let i = 0; i < rgba.length; i += 4) {
    const a = rgba[i + 3] / 255;
    for (let c = 0; c < 3; c++) rgba[i + c] = Math.round(rgba[i + c] * a + 255 * (1 - a));
    rgba[i + 3] = 255;
  }
  return { ...image, rgba };
}

function compare(a, b) {
  if (a.width !== b.width || a.height !== b.height) return { size: [a.width, a.height, b.width, b.height] };
  const diffs = [];
  let differ = 0;
  for (let i = 0; i < a.rgba.length; i += 4) {
    let d = 0;
    for (let c = 0; c < 3; c++) {
      const v = Math.abs(a.rgba[i + c] - b.rgba[i + c]);
      diffs.push(v);
      d = Math.max(d, v);
    }
    if (d) differ++;
  }
  diffs.sort((x, y) => x - y);
  return { differ, mean: Number((diffs.reduce((s, d) => s + d, 0) / diffs.length).toFixed(3)), p99: diffs[Math.floor(diffs.length * 0.99)], max: diffs.at(-1) };
}

const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = [];
let failed = 0;
const url = (style, camera, ratio = 1) => `${origin}/bench/query/index.html?style=/bench/dist/export-${style}.json&camera=${encodeURIComponent(JSON.stringify(camera))}&ratio=${ratio}`;
try {
  for (const [name, v] of Object.entries(views)) {
    const page = await browser.newPage({ viewport: { width: 800, height: 1200 } });
    page.on("pageerror", (e) => console.log(name, "pageerror", e.message));
    await page.goto(url(v.style, v.camera));
    await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    const [whole, parts, one] = await images(page, [{ pixelRatio: v.ratio }, { pixelRatio: v.ratio, maxSize: v.maxSize }, { pixelRatio: 1 }]);
    // The attribution is a DOM overlay, not part of the image.
    await page.addStyleTag({ content: "#mbmap > div { visibility: hidden !important; }" });
    const screen = decodePng(await page.screenshot({ clip: { x: 0, y: 0, width: 800, height: 600 } }));
    const split = compare(whole, parts);
    const shown = compare(overWhite(one), screen);
    const ok = split.mean <= LIMITS.split.mean && split.p99 <= LIMITS.split.p99 && shown.differ === 0;
    if (!ok) failed++;
    results.push({ view: name, ok, size: [whole.width, whole.height], maxSize: v.maxSize, split, screen: shown });
    await page.close();
  }
  const camera = { center: [139.7671, 35.6812], zoom: 14.6, bearing: 20, pitch: 0 };
  const page = await browser.newPage({ viewport: { width: 800, height: 1200 }, deviceScaleFactor: 2 });
  page.on("pageerror", (e) => console.log("raster", "pageerror", e.message));
  await page.goto(url("raster", camera, 2));
  await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
  const [image] = await images(page, [{ pixelRatio: 2, maxSize: 700 }]);
  const maplibre = decodePng(await page.screenshot({ clip: { x: 0, y: 600, width: 800, height: 600 } }));
  const r = compare(image, maplibre);
  const ok = r.mean <= LIMITS.maplibre.mean && r.p99 <= LIMITS.maplibre.p99;
  if (!ok) failed++;
  results.push({ view: "raster-2x-vs-maplibre", ok, size: [image.width, image.height], maxSize: 700, ...r });
  await page.close();
} finally {
  await browser.close();
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/export-golden.json"), JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, limits: LIMITS, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
if (failed) process.exit(1);
