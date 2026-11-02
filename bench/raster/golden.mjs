// Raster sources and layers drawn by mbmap and MapLibre GL JS 6.16.0 side by
// side in Chromium (bench/query's page): GSI's standard map (bench fixtures,
// 256 px tiles at z14) under several raster paints, compared pixel by pixel.
// Writes bench/results/raster-golden.json. Needs `npm --prefix npm run build`.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { decodePng } from "../lib/png.mjs";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";

const paints = {
  plain: {},
  adjusted: {
    "raster-opacity": 0.6, "raster-hue-rotate": 90, "raster-saturation": -0.5,
    "raster-contrast": 0.3, "raster-brightness-min": 0.2, "raster-brightness-max": 0.9,
  },
  nearest: { "raster-resampling": "nearest" },
  zoomed: { "raster-opacity": ["interpolate", ["linear"], ["zoom"], 14, 0.2, 16, 1] },
};
const cameras = { z14: { center: [139.7671, 35.6812], zoom: 14, bearing: 0, pitch: 0 }, z15: { center: [139.7671, 35.6812], zoom: 15.3, bearing: 20, pitch: 0 } };
// Per-channel differences allowed: the images agree to rounding, but where a
// turned map samples the nearest texel, a pixel on a texel edge may pick the other.
const LIMITS = { mean: 0.05, p99: 1 };

await mkdir(path.join(ROOT, "bench/dist"), { recursive: true });
const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = [];
let failed = 0;
try {
  for (const [name, paint] of Object.entries(paints)) {
    const style = {
      version: 8,
      sources: { std: { type: "raster", tiles: ["{origin}/bench/fixtures/gsi-std/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 14, maxzoom: 14 } },
      layers: [{ id: "bg", type: "background", paint: { "background-color": "#ffffff" } }, { id: "std", type: "raster", source: "std", paint }],
    };
    const file = `bench/dist/raster-${name}.json`;
    await writeFile(path.join(ROOT, file), JSON.stringify(style));
    for (const [view, camera] of Object.entries(cameras)) {
      const page = await browser.newPage({ viewport: { width: 800, height: 1200 } });
      page.on("pageerror", (e) => console.log(name, "pageerror", e.message));
      await page.goto(`${origin}/bench/query/index.html?style=/${file}&camera=${encodeURIComponent(JSON.stringify(camera))}`);
      await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
      const shot = (y) => page.screenshot({ clip: { x: 0, y, width: 800, height: 600 } }).then((b) => decodePng(b));
      const [a, b] = [await shot(0), await shot(600)];
      const diffs = [];
      for (let i = 0; i < a.rgba.length; i += 4) for (let c = 0; c < 3; c++) diffs.push(Math.abs(a.rgba[i + c] - b.rgba[i + c]));
      diffs.sort((x, y) => x - y);
      const mean = diffs.reduce((s, d) => s + d, 0) / diffs.length;
      const p99 = diffs[Math.floor(diffs.length * 0.99)];
      const ok = mean <= LIMITS.mean && p99 <= LIMITS.p99;
      if (!ok) failed++;
      results.push({ paint: name, view, ok, mean: Number(mean.toFixed(3)), p99, max: diffs.at(-1) });
      await page.close();
    }
  }
} finally {
  await browser.close();
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/raster-golden.json"), JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, limits: LIMITS, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
if (failed) process.exit(1);
