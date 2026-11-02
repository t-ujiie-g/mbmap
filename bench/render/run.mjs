// mbmap vs MapLibre, same style, tiles and camera script, in Chromium with the Metal GPU.
// Usage: node render/run.mjs [--runs=11] [--uncapped] [--labels] [--terrain] [--extrusion] [--pitch=N]
// Writes bench/results/render-chromium[-labels][-terrain][-extrusion][-pitchN][-uncapped].json.
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { gzipSync } from "node:zlib";
import path from "node:path";
import { build } from "esbuild";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";
import { decodePng, encodePng, gsiToTerrarium } from "../lib/png.mjs";

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1] ?? d;
const runs = Number(arg("runs", 11));
const uncapped = process.argv.includes("--uncapped");
// --labels adds the label layers of bench/pages/basic, drawn from local fonts by both engines.
const labels = process.argv.includes("--labels");
// --terrain drapes the map on the gsi-dem fixtures as Terrarium, with a sky, pitched 45 degrees
// (at 60 MapLibre leaves distant terrain blank: below the vector source's minzoom).
const terrain = process.argv.includes("--terrain");
// --extrusion draws the buildings as fill-extrusion (GSI tiles have no heights:
// 30 m for sturdy buildings, 8 m for others), pitched 45 degrees by default.
const extrusion = process.argv.includes("--extrusion");
const pitchArg = arg("pitch", null);
const pitch = Number(pitchArg ?? (terrain || extrusion ? 45 : 0));
const styleVariant = `${labels ? "-labels" : ""}${terrain ? "-terrain" : ""}${extrusion ? "-extrusion" : ""}`;
const variant = `${styleVariant}${pitchArg !== null ? `-pitch${pitch}` : ""}`;
const style = styleVariant ? `bench/dist/style${styleVariant}.json` : "bench/maplibre/style.json";
if (styleVariant) {
  const base = JSON.parse(await readFile(path.join(ROOT, "bench/maplibre/style.json"), "utf8"));
  if (labels) {
    const basic = JSON.parse(await readFile(path.join(ROOT, "bench/pages/basic/style.json"), "utf8"));
    base.layers.push(...basic.layers.filter((l) => l.type === "symbol"));
  }
  if (terrain) {
    // Terrarium copies of the z14 fixtures, and z13 and z12 halved from them
    // (no data as 0 m) for the distant tiles of a pitched view.
    const from = path.join(ROOT, "bench/fixtures/gsi-dem/14");
    const levels = { 14: new Map() };
    for (const x of await readdir(from))
      for (const f of await readdir(path.join(from, x))) {
        const { width, rgba } = decodePng(await readFile(path.join(from, x, f)));
        levels[14].set(`${x}/${parseInt(f)}`, { size: width, rgba: gsiToTerrarium(rgba) });
      }
    const height = (t, i) => t.rgba[i * 4] * 256 + t.rgba[i * 4 + 1] + t.rgba[i * 4 + 2] / 256;
    for (let z = 13; z >= 12; z--) {
      levels[z] = new Map();
      for (const key of levels[z + 1].keys()) {
        const [x, y] = key.split("/").map((v) => v >> 1);
        if (levels[z].has(`${x}/${y}`)) continue;
        const size = 256, rgba = new Uint8Array(size * size * 4);
        for (let py = 0; py < size; py++)
          for (let px = 0; px < size; px++) {
            const child = levels[z + 1].get(`${x * 2 + (px >> 7)}/${y * 2 + (py >> 7)}`);
            const cx = (px & 127) * 2, cy = (py & 127) * 2;
            const v = child ? (height(child, cy * size + cx) + height(child, cy * size + cx + 1) + height(child, (cy + 1) * size + cx) + height(child, (cy + 1) * size + cx + 1)) / 4 : 32768;
            const t = Math.round(v * 256);
            rgba.set([t >> 16, (t >> 8) & 0xff, t & 0xff, 255], (py * size + px) * 4);
          }
        levels[z].set(`${x}/${y}`, { size, rgba });
      }
    }
    for (const [z, tiles] of Object.entries(levels))
      for (const [key, t] of tiles) {
        const file = path.join(ROOT, `bench/dist/dem-terrarium/${z}/${key}.png`);
        await mkdir(path.dirname(file), { recursive: true });
        await writeFile(file, encodePng(t.size, t.size, t.rgba));
      }
    base.sources.dem = { type: "raster-dem", tiles: ["{origin}/bench/dist/dem-terrarium/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 12, maxzoom: 14, encoding: "terrarium" };
    base.terrain = { source: "dem", exaggeration: 1 };
    base.sky = { "sky-color": "#88C6FC", "horizon-color": "#ffffff", "fog-color": "#ffffff" };
  }
  if (extrusion) {
    const at = base.layers.findIndex((l) => l.id === "building");
    base.layers.splice(at, 2, {
      id: "building-3d", type: "fill-extrusion", source: "gsi", "source-layer": "building",
      paint: {
        "fill-extrusion-color": ["match", ["get", "ftCode"], 3103, "#d9c9b6", "#e3ddd3"],
        "fill-extrusion-height": ["match", ["get", "ftCode"], 3103, 30, 8],
      },
    });
  }
  await mkdir(path.join(ROOT, "bench/dist"), { recursive: true });
  await writeFile(path.join(ROOT, style), JSON.stringify(base));
}
const dpr = 2;

// Shipped sizes: mbmap's js bundle minified as a bundler would, its worker
// glue and wasm; MapLibre's dist files.
const gz = async (file) => gzipSync(await readFile(path.join(ROOT, file)), { level: 9 }).length;
await build({ entryPoints: [path.join(ROOT, "_build/js/release/build/bundle/main/main.js")], bundle: true, minify: true, format: "esm", outfile: path.join(ROOT, "bench/dist/mbmap-main.min.js"), logLevel: "warning" });
await build({ entryPoints: [path.join(ROOT, "worker/js/worker.mjs")], bundle: true, minify: true, format: "esm", outfile: path.join(ROOT, "bench/dist/mbmap-worker.min.js"), logLevel: "warning" });
const sizes = {
  mbmap: { main: await gz("bench/dist/mbmap-main.min.js"), worker: await gz("bench/dist/mbmap-worker.min.js") + await gz("_build/wasm-gc/release/build/worker/worker.wasm") },
  maplibre: { main: await gz("bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs"), worker: await gz("bench/node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs") },
};

const { server, origin } = await serve();
const browser = await chromium.launch({ args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist", ...(uncapped ? ["--disable-gpu-vsync", "--disable-frame-rate-limit"] : [])] });
const results = { mbmap: [], maplibre: [] };
for (let i = 0; i < runs; i++) {
  for (const engine of ["mbmap", "maplibre"]) {
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: dpr });
    const page = await context.newPage();
    page.on("pageerror", (e) => console.log(engine, "pageerror", e.message));
    await page.goto(`${origin}/bench/render/index.html?engine=${engine}&dpr=${dpr}&pitch=${pitch}&style=/${style}`);
    const t0 = Date.now();
    await page.waitForFunction(() => window.__result, null, { timeout: 120000, polling: 500 }).catch((e) => {
      throw new Error(`${engine}, run ${i}: no result after ${Date.now() - t0} ms (${e.message})`);
    });
    results[engine].push(await page.evaluate(() => window.__result));
    await context.close();
  }
}
await browser.close();
server.close();

const med = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };
const summary = {};
for (const [engine, rs] of Object.entries(results)) {
  summary[engine] = {
    idle: med(rs.map((r) => r.marks.idle)),
    scenarios: Object.fromEntries(rs[0].scenarios.map((s, j) => [s.name, {
      frameMeanMs: med(rs.map((r) => r.scenarios[j].frameMs.mean)),
      frameP95Ms: med(rs.map((r) => r.scenarios[j].frameMs.p95)),
      over20ms: med(rs.map((r) => r.scenarios[j].over20ms)),
      rafCpuP50Ms: med(rs.map((r) => r.scenarios[j].rafCpuMs.p50)),
      rafCpuP95Ms: med(rs.map((r) => r.scenarios[j].rafCpuMs.p95)),
    }])),
  };
}
const out = {
  env: { browser: `chromium ${browser.version()}`, uncapped, viewport: "1280x800", dpr, pitch, style: [labels ? "bench/maplibre/style.json + bench/pages/basic labels" : "bench/maplibre/style.json", ...(terrain ? ["terrain on bench/fixtures/gsi-dem as Terrarium, z12-13 halved from it, sky"] : []), ...(extrusion ? ["buildings extruded 30 m (ftCode 3103) or 8 m"] : [])].join(", ") },
  params: { runs, statistic: "median of runs" }, sizes, summary, runs: results,
};
await writeFile(path.join(ROOT, `bench/results/render-chromium${variant}${uncapped ? "-uncapped" : ""}.json`), JSON.stringify(out, null, 2) + "\n");
console.log(JSON.stringify({ sizes, summary }, null, 2));
