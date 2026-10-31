// MapLibre baseline: bundle size, first render time and frame times.
// Usage: node maplibre/run.mjs [--throttle=4] [--headed] [--runs=5]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { gzipSync, brotliCompressSync } from "node:zlib";
import path from "node:path";
import { chromium } from "playwright";
import { serve, ROOT } from "../lib/serve.mjs";

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1] ?? d;
const throttle = Number(arg("throttle", 1));
const runs = Number(arg("runs", 5));
const headed = process.argv.includes("--headed");
const dpr = Number(arg("dpr", 2));
// Uncapped: no vsync / frame rate limit, so frame intervals show real headroom.
const uncapped = process.argv.includes("--uncapped");

const dist = path.join(ROOT, "bench/node_modules/maplibre-gl/dist");
const sizes = {};
for (const f of ["maplibre-gl.mjs", "maplibre-gl-worker.mjs", "maplibre-gl.css"]) {
  const b = await readFile(path.join(dist, f));
  sizes[f] = { raw: b.length, gzip: gzipSync(b, { level: 9 }).length, brotli: brotliCompressSync(b).length };
}

const { server, origin } = await serve();
const browser = await chromium.launch({ headless: !headed, args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist", ...(uncapped ? ["--disable-gpu-vsync", "--disable-frame-rate-limit"] : [])] });
const results = [];
for (let i = 0; i < runs; i++) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: dpr });
  const page = await context.newPage();
  if (throttle > 1) {
    const cdp = await context.newCDPSession(page);
    await cdp.send("Emulation.setCPUThrottlingRate", { rate: throttle });
  }
  await page.goto(`${origin}/bench/maplibre/index.html?dpr=${dpr}`);
  await page.waitForFunction(() => window.__result, null, { timeout: 180000, polling: 500 });
  results.push(await page.evaluate(() => window.__result));
  await context.close();
}
await browser.close();
server.close();

const med = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };
const summary = {
  importEnd: med(results.map((r) => r.marks.importEnd)),
  load: med(results.map((r) => r.marks.load)),
  idle: med(results.map((r) => r.marks.idle)),
  scenarios: Object.fromEntries(results[0].scenarios.map((s, j) => [s.name, {
    frameMeanMs: med(results.map((r) => r.scenarios[j].frameMs.mean)),
    frameP95Ms: med(results.map((r) => r.scenarios[j].frameMs.p95)),
    frameMaxMs: med(results.map((r) => r.scenarios[j].frameMs.max)),
    over20ms: med(results.map((r) => r.scenarios[j].over20ms)),
    renderCpuP50Ms: med(results.map((r) => r.scenarios[j].renderCpuMs.p50)),
    renderCpuP95Ms: med(results.map((r) => r.scenarios[j].renderCpuMs.p95)),
    longTasks: med(results.map((r) => r.scenarios[j].longTasks.length)),
  }])),
};
const out = {
  env: { browser: `chromium ${browser.version()}`, headless: !headed, uncapped, cpuThrottle: throttle, viewport: "1280x800", dpr, renderer: results[0].renderer, maplibre: results[0].version, userAgent: results[0].userAgent },
  params: { runs, statistic: "median of runs" }, sizes, summary, runs: results,
};
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
const name = `maplibre-render-chromium${headed ? "-headed" : ""}${uncapped ? "-uncapped" : ""}${throttle > 1 ? `-cpu${throttle}x` : ""}.json`;
await writeFile(path.join(ROOT, "bench/results", name), JSON.stringify(out, null, 2) + "\n");
console.log(JSON.stringify({ env: out.env, sizes, summary }, null, 2));
