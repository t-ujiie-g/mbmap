// Raster sources and paints vs MapLibre GL JS 6.16.0 in Chromium, pixel by pixel, on GSI's standard
// map (z14 fixtures, and the world at z0-3 for the globe), and the tile URLs both request from
// templates with every placeholder.
// Writes bench/results/raster-golden.json. Needs `npm --prefix npm run build`.
import { mkdir, readFile, writeFile } from "node:fs/promises";
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
  resampling: { resampling: "nearest" },
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

  // The globe (style `projection`), on the whole world's standard map at zooms 0 to 3; zoom 11.5 is
  // halfway into mercator, zoom 12.5 past it, and a sky brings the atmosphere.
  const world = { type: "raster", tiles: ["{origin}/bench/fixtures/gsi-std-world/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 0, maxzoom: 3 };
  const globeStyles = {
    globe: { projection: { type: "globe" } },
    "globe-sky": { projection: { type: "globe" }, sky: {} },
    "vertical-perspective": { projection: { type: "vertical-perspective" } },
  };
  const globeCameras = {
    z0: { center: [0, 0], zoom: 0.3, bearing: 0, pitch: 0 },
    z1: { center: [139.7, 35.7], zoom: 1, bearing: 0, pitch: 0 },
    z2: { center: [139.7, 35.7], zoom: 2.3, bearing: 30, pitch: 40 },
    z5: { center: [-100, 70], zoom: 5, bearing: -120, pitch: 60 },
    z11: { center: [139.7671, 35.6812], zoom: 11.5, bearing: 10, pitch: 30 },
    z12: { center: [139.7671, 35.6812], zoom: 12.5, bearing: 0, pitch: 0 },
  };
  for (const [name, extra] of Object.entries(globeStyles)) {
    const style = {
      version: 8, ...extra,
      sources: { std: world },
      layers: [{ id: "bg", type: "background", paint: { "background-color": "#203040" } }, { id: "std", type: "raster", source: "std" }],
    };
    const file = `bench/dist/raster-${name}.json`;
    await writeFile(path.join(ROOT, file), JSON.stringify(style));
    for (const [view, camera] of Object.entries(globeCameras)) {
      if (name !== "globe" && view !== "z1" && view !== "z11") continue;
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

  // Each engine's template carries its name, so the requests of the two can be told apart.
  const tile = await readFile(path.join(ROOT, "bench/fixtures/gsi-std/14/14552/6451.png"));
  const placeholders = "p={prefix}&q={quadkey}&r={ratio}&b={bbox-epsg-3857}&c={bbox}&z={z}&x={x}&y={y}";
  const urlStyle = (engine, scheme) => ({
    version: 8,
    ...(scheme === "globe" ? { projection: { type: "globe" } } : {}),
    sources: {
      s: {
        type: "raster", scheme: scheme === "globe" ? "xyz" : scheme, tileSize: 256, minzoom: 0, maxzoom: 14,
        tiles: ["a", "b"].map((host) => `{origin}/bench/fixtures/gsi-std/{z}/{x}/{y}.png?engine=${engine}&host=${host}&${placeholders}`),
      },
    },
    layers: [{ id: "s", type: "raster", source: "s" }],
  });
  for (const scheme of ["xyz", "tms", "globe"]) {
    for (const ratio of scheme === "globe" ? [1] : [1, 2]) {
      const views = scheme === "globe"
        ? { z1: globeCameras.z1, z2: globeCameras.z2, z5: globeCameras.z5, z11: globeCameras.z11 }
        : { ...cameras, z3: { center: [139.7671, 35.6812], zoom: 3.4, bearing: 0, pitch: 0 } };
      for (const [view, camera] of Object.entries(views)) {
        const files = {};
        for (const engine of ["mbmap", "maplibre"]) {
          files[engine] = `bench/dist/raster-urls-${engine}.json`;
          await writeFile(path.join(ROOT, files[engine]), JSON.stringify(urlStyle(engine, scheme)));
        }
        const page = await browser.newPage({ viewport: { width: 800, height: 1200 }, deviceScaleFactor: ratio });
        const urls = { mbmap: new Set(), maplibre: new Set() };
        const record = (url) => {
          const u = new URL(url);
          const engine = u.searchParams.get("engine");
          if (!urls[engine]) return;
          u.searchParams.delete("engine");
          urls[engine].add(u.pathname + u.search);
        };
        // Every tile is answered with one PNG: on a 404 MapLibre would also ask for the parent tiles.
        await page.route((u) => u.searchParams.has("engine"), (route) => {
          record(route.request().url());
          return route.fulfill({ contentType: "image/png", body: tile });
        });
        page.on("pageerror", (e) => console.log("urls pageerror", e.message));
        await page.goto(`${origin}/bench/query/index.html?style=/${files.mbmap}&mlstyle=/${files.maplibre}&ratio=${ratio}&camera=${encodeURIComponent(JSON.stringify(camera))}`);
        await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
        const only = (a, b) => [...urls[a]].filter((u) => !urls[b].has(u)).sort();
        const [mbOnly, mlOnly] = [only("mbmap", "maplibre"), only("maplibre", "mbmap")];
        const ok = urls.mbmap.size > 0 && mbOnly.length === 0 && mlOnly.length === 0;
        if (!ok) failed++;
        results.push({ urls: scheme, ratio, view, ok, requested: urls.mbmap.size, mbmapOnly: mbOnly.slice(0, 3), maplibreOnly: mlOnly.slice(0, 3) });
        await page.close();
      }
    }
  }
} finally {
  await browser.close();
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/raster-golden.json"), JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, limits: LIMITS, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
if (failed) process.exit(1);
