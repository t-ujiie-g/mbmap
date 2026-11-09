// Map.setClipping vs CesiumJS 1.146.0's ClippingPlaneCollection and ClippingPolygonCollection on PLATEAU's
// buildings (plateau-chiyoda), the same planes and polygons at the same cameras: where buildings are drawn
// (any pixel off a black background), each engine against itself unclipped and against the other.
// Lights differ between them, so shapes are compared, not colors. Usage: node cesium/clip.mjs after
// `npm --prefix npm run build`; writes bench/results/cesium-clip.json and bench/results/cesium/clip-*.png.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";
import { decodePng } from "../lib/png.mjs";
import { HEIGHT, VIEWS, WIDTH } from "./views.mjs";

const ORIGIN = [139.7671, 35.6812, 0];
const SQUARE = (r) => {
  const [dx, dy] = [r / (111320 * Math.cos((ORIGIN[1] * Math.PI) / 180)), r / 110950];
  return [[ORIGIN[0] - dx, ORIGIN[1] - dy], [ORIGIN[0] + dx, ORIGIN[1] - dy], [ORIGIN[0] + dx, ORIGIN[1] + dy], [ORIGIN[0] - dx, ORIGIN[1] + dy]];
};
/** The clippings compared: a half space, a box (every plane keeps), a cut below a height, a hole and its inverse. */
const CLIPS = {
  north: { origin: ORIGIN, planes: [[0, 1, 0, 0]] },
  box: { origin: ORIGIN, unionClippingRegions: true, planes: [[1, 0, 0, 120], [-1, 0, 0, 120], [0, 1, 0, 120], [0, -1, 0, 120], [0, 0, -1, 40]] },
  either: { origin: ORIGIN, planes: [[1, 0, 0, -50], [0, 0, -1, 8]] },
  hole: { origin: ORIGIN, polygons: [SQUARE(150)] },
  island: { origin: ORIGIN, polygons: [SQUARE(60)], inverse: true },
};
/** How many more pixels (a share of those drawn unclipped) the engines may disagree on clipped than unclipped. */
const SLACK = 0.02;

const { server, origin } = await serve();
const browser = await chromium.launch();
const SHOTS = path.join(ROOT, "bench/results/cesium");
await mkdir(SHOTS, { recursive: true });

/** Where buildings are drawn: pixels off the black background the pages clip over. */
function mask(png) {
  const { rgba } = decodePng(png);
  const out = new Uint8Array(WIDTH * HEIGHT);
  for (let i = 0; i < out.length; i++) out[i] = rgba[i * 4] + rgba[i * 4 + 1] + rgba[i * 4 + 2] > 24 ? 1 : 0;
  return out;
}
/** The pixels only one of two masks draws, as a share of `whole` (the pixels either engine draws unclipped). */
function apart(a, b, whole) {
  let one = 0;
  for (let i = 0; i < a.length; i++) one += a[i] ^ b[i];
  return one / whole;
}

const results = [];
let failed = 0;
for (const v of [0, 2]) {
  const masks = {};
  for (const engine of ["mbmap", "cesium"]) {
    masks[engine] = {};
    // A fresh page per clipping: CesiumJS stops rendering when a tileset's clipping is replaced.
    for (const [name, c] of [["none", null], ...Object.entries(CLIPS)]) {
      const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT }, deviceScaleFactor: 1 });
      const errors = [];
      page.on("pageerror", (e) => errors.push(e.message));
      await page.goto(`${origin}/bench/cesium/${engine}.html?view=${v}`);
      await page.waitForFunction(() => window.__pageReady, null, { timeout: 60000 });
      await page.evaluate(() => window.__run());
      await page.evaluate((c) => window.__clip(c), c);
      const shot = await page.screenshot();
      masks[engine][name] = mask(shot);
      if (c) await writeFile(path.join(SHOTS, `clip-${VIEWS[v].name}-${name}-${engine}.png`), shot);
      if (errors.length) throw new Error(`${engine} ${name}: ${errors.join("; ")}`);
      await page.close();
    }
  }
  const whole = masks.mbmap.none.reduce((n, x, i) => n + (x | masks.cesium.none[i]), 0);
  const base = apart(masks.mbmap.none, masks.cesium.none, whole);
  for (const name of Object.keys(CLIPS)) {
    const between = apart(masks.mbmap[name], masks.cesium[name], whole);
    const cut = { mbmap: apart(masks.mbmap.none, masks.mbmap[name], whole), cesium: apart(masks.cesium.none, masks.cesium[name], whole) };
    const ok = between <= base + SLACK && cut.mbmap > 0.05 && cut.cesium > 0.05;
    if (!ok) failed++;
    results.push({ view: VIEWS[v].name, clip: name, unclipped: base, between, cut, ok });
  }
}
await browser.close();
server.close();
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/cesium-clip.json"), JSON.stringify({ date: new Date().toISOString(), slack: SLACK, results }, null, 2) + "\n");
console.table(results.map((r) => ({ ...r, unclipped: r.unclipped.toFixed(3), between: r.between.toFixed(3), cut: `${r.cut.mbmap.toFixed(2)} / ${r.cut.cesium.toFixed(2)}` })));
if (failed) process.exitCode = 1;
