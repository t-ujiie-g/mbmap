// mbmap vs MapLibre with the same style, tiles and camera script, in Chromium
// with the Metal GPU. Usage: node render/run.mjs [--runs=11] [--uncapped] [--labels]
// Writes bench/results/render-chromium[-labels][-uncapped].json.
import { readFile, writeFile } from "node:fs/promises";
import { gzipSync } from "node:zlib";
import path from "node:path";
import { build } from "esbuild";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1] ?? d;
const runs = Number(arg("runs", 11));
const uncapped = process.argv.includes("--uncapped");
// The style with the label layers of examples/basic, drawn from local fonts by both engines.
const labels = process.argv.includes("--labels");
const style = labels ? "bench/maplibre/style-labels.json" : "bench/maplibre/style.json";
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
    await page.goto(`${origin}/bench/render/index.html?engine=${engine}&dpr=${dpr}&style=/${style}`);
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
  env: { browser: `chromium ${browser.version()}`, uncapped, viewport: "1280x800", dpr, style },
  params: { runs, statistic: "median of runs" }, sizes, summary, runs: results,
};
await writeFile(path.join(ROOT, `bench/results/render-chromium${labels ? "-labels" : ""}${uncapped ? "-uncapped" : ""}.json`), JSON.stringify(out, null, 2) + "\n");
console.log(JSON.stringify({ sizes, summary }, null, 2));
