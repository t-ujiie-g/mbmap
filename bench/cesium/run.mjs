// mbmap/3d's tilesLayer vs CesiumJS 1.146.0 on PLATEAU's buildings (bench/fixtures/plateau-chiyoda),
// in Chromium at the same viewport and cameras (bench/cesium/views.mjs): tiles selected, tile requests
// and bytes, time from adding the layer until the selection settles, screenshots side by side,
// per-frame CPU of the rAF callbacks over an orbit, and the gzip bytes of the code each page loads.
// Usage: node cesium/run.mjs [--runs=3] [--gpu]. Needs `npm --prefix npm run build`.
// Writes bench/results/cesium.json and bench/results/cesium/*.png (gitignored).
import { mkdir, writeFile } from "node:fs/promises";
import { gzipSync } from "node:zlib";
import path from "node:path";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";
import { decodePng, encodePng } from "../lib/png.mjs";
import { arg } from "../lib/args.mjs";
import { HEIGHT, ORBIT_FRAMES, VIEWS, WIDTH, cameraDistance } from "./views.mjs";

const runs = Number(arg("runs", 3));
// Frame timings count only on the M2's GPU (AGENTS §5); headless Chromium otherwise uses SwiftShader.
const gpu = process.argv.includes("--gpu");
const ENGINES = ["mbmap", "cesium"];
const FIXTURE = "/bench/fixtures/plateau-chiyoda/";
const CODE = { mbmap: "/npm/dist/", cesium: "/bench/node_modules/cesium/Build/Cesium/" };
const SHOTS = path.join(ROOT, "bench/results/cesium");
await mkdir(SHOTS, { recursive: true });

const { server, origin } = await serve();
const browser = await chromium.launch({ args: gpu ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [] });
const median = (xs) => [...xs].sort((a, b) => a - b)[xs.length >> 1];
const gz = (body) => gzipSync(body, { level: 9 }).length;

/** One page of `engine` at view `v`: loads, settles, a screenshot and an orbit; what it fetched. */
async function visit(engine, v) {
  const context = await browser.newContext({ viewport: { width: WIDTH, height: HEIGHT }, deviceScaleFactor: 1 });
  const outside = [];
  await context.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (url.protocol === "data:" || url.protocol === "blob:" || url.origin === origin) return route.continue();
    outside.push(url.href);
    return route.abort();
  });
  const responses = [];
  const errors = [];
  const page = await context.newPage();
  page.on("response", (r) => responses.push(r));
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => m.type() === "error" && !m.text().startsWith("Failed to load resource") && errors.push(m.text()));
  await page.goto(`${origin}/bench/cesium/${engine}.html?view=${v}`);
  await page.waitForFunction(() => window.__pageReady, null, { timeout: 60000 });
  const run = await page.evaluate(() => window.__run());
  const shot = await page.screenshot();
  // Every response until settled; the code once per file.
  const fetched = [];
  for (const r of responses) {
    const url = new URL(r.url());
    if (url.origin !== origin) continue;
    fetched.push([url.pathname, r.status(), r.status() < 300 ? await r.body().catch(() => Buffer.alloc(0)) : null]);
  }
  const orbit = await page.evaluate(() => window.__orbit());
  const renderer = await page.evaluate(() => window.__renderer());
  await context.close();
  if (outside.length) throw new Error(`${engine} asked for ${outside.length} URLs outside ${origin}: ${outside.slice(0, 5).join(", ")}`);
  // The fixture holds the tiles loaders.gl's selection reaches; others answer 404.
  const missing = fetched.filter(([p, status]) => p.startsWith(FIXTURE) && status === 404).map(([p]) => p.slice(FIXTURE.length));
  const tiles = fetched.filter(([p, status]) => p.startsWith(FIXTURE) && status < 300);
  const code = [...new Map(fetched.filter(([p, status]) => p.startsWith(CODE[engine]) && status < 300).map(([p, , b]) => [p, b]))];
  const isCode = (p) => /\.(m?js|wasm)$/.test(p);
  return {
    run, orbit, renderer, errors, shot,
    requests: { tiles: tiles.length, b3dm: tiles.filter(([p]) => p.endsWith(".b3dm")).length, json: tiles.filter(([p]) => p.endsWith(".json")).length, bytes: tiles.reduce((n, [, , b]) => n + b.length, 0), missing },
    code: {
      gzip: code.filter(([p]) => isCode(p)).reduce((n, [, b]) => n + gz(b), 0),
      assetsGzip: code.filter(([p]) => !isCode(p)).reduce((n, [, b]) => n + gz(b), 0),
      files: Object.fromEntries(code.map(([p, b]) => [p.slice(CODE[engine].length), gz(b)])),
    },
  };
}

/** Two screenshots side by side, mbmap on the left. */
function sideBySide(left, right) {
  const [a, b] = [decodePng(left), decodePng(right)];
  const gap = 8;
  const width = a.width + gap + b.width;
  const rgba = new Uint8Array(width * a.height * 4).fill(128);
  for (let y = 0; y < a.height; y++) {
    rgba.set(a.rgba.subarray(y * a.width * 4, (y + 1) * a.width * 4), y * width * 4);
    rgba.set(b.rgba.subarray(y * b.width * 4, (y + 1) * b.width * 4), (y * width + a.width + gap) * 4);
  }
  return encodePng(width, a.height, rgba);
}

const views = [];
let renderers = {};
let sizes = {};
for (const [v, view] of VIEWS.entries()) {
  const out = { ...view, cameraDistanceMeters: cameraDistance(view) };
  const shots = {};
  for (const engine of ENGINES) {
    const visits = [];
    for (let i = 0; i < runs; i++) visits.push(await visit(engine, v));
    const [first] = visits;
    shots[engine] = first.shot;
    await writeFile(path.join(SHOTS, `${view.name}-${engine}.png`), first.shot);
    renderers[engine] = first.renderer;
    sizes[engine] = first.code;
    const { contents, ...run } = first.run;
    out[engine] = {
      ...run,
      settleMs: median(visits.map((x) => x.run.settleMs)),
      settleMsRuns: visits.map((x) => Math.round(x.run.settleMs)),
      requests: first.requests,
      sameEveryRun: visits.every((x) => x.requests.tiles === first.requests.tiles && x.run.selected === first.run.selected),
      orbitCpuMs: { frames: first.orbit.frames, p50: median(visits.map((x) => x.orbit.p50)), p95: median(visits.map((x) => x.orbit.p95)), max: median(visits.map((x) => x.orbit.max)) },
      contents,
      errors: first.errors,
    };
    console.log(view.name, engine, JSON.stringify({ selected: run.selected, settleMs: Math.round(out[engine].settleMs), requests: first.requests, orbit: out[engine].orbitCpuMs }));
  }
  const both = new Set(out.mbmap.contents.filter((c) => out.cesium.contents.includes(c)));
  out.sharedContents = both.size;
  await writeFile(path.join(SHOTS, `${view.name}.png`), sideBySide(shots.mbmap, shots.cesium));
  views.push(out);
}
const result = {
  env: { browser: `chromium ${browser.version()}`, gpu, renderers, viewport: `${WIDTH}x${HEIGHT}`, dpr: 1, cesium: "1.146.0" },
  params: {
    runs, statistic: "median of runs (settle and orbit); tiles and bytes from the first run",
    orbit: `${ORBIT_FRAMES} frames, bearing +1° per frame, after settling`,
    selection: "maximumScreenSpaceError 8 on both; Cesium without dynamic or foveated SSE, skipLevelOfDetail off, cullRequestsWhileMoving off",
    height: "mbmap tilesLayer height -36.7; Cesium modelMatrix translating the tileset 36.7 m down its bounding sphere center's ellipsoid normal",
    camera: "MapLibre's camera (vertical fov 36.87°, distance 1.5 viewport heights at the center latitude's meters per pixel) as Cesium's lookAt of heading = bearing, pitch = pitch - 90° around the center at 0 m; Cesium's fov the horizontal one",
    code: "gzip -9 of the .js/.mjs/.wasm each page fetched from npm/dist or cesium/Build/Cesium (its prebuilt IIFE Cesium.js carries the workers, CESIUM_WORKERS, started from blobs); assetsGzip is the rest (css, json, images)",
  },
  sizes, views,
};
await browser.close();
server.close();
await writeFile(path.join(ROOT, "bench/results/cesium.json"), JSON.stringify(result, null, 2) + "\n");
console.log(JSON.stringify({ sizes: Object.fromEntries(Object.entries(sizes).map(([k, s]) => [k, { gzip: s.gzip, assetsGzip: s.assetsGzip }])) }));
console.log(`screenshots: ${SHOTS}`);
