// queryRenderedFeatures and querySourceFeatures of mbmap against MapLibre GL JS
// 6.16.0 in Chromium: the same style, tiles (bench fixtures) and camera, the
// same points and boxes; every result must list the same features in the same
// order. Writes bench/results/query-golden.json. Needs `npm --prefix npm run build`.
//
// Known differences, left out of the asks: on a tilted view MapLibre also keeps
// tiles whose bounding box only touches the view's frustum, which mbmap's
// covering leaves out, so queries of the whole view and of a source differ by
// those tiles' features. Extrusions that meet a query at the same depth (GSI has
// many buildings both as a polygon and as its outline) are ordered by rounding,
// so such pairs are put in one order before comparing.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";

const base = JSON.parse(await readFile(path.join(ROOT, "bench/maplibre/style.json"), "utf8"));
const extruded = structuredClone(base);
const at = extruded.layers.findIndex((l) => l.id === "building");
extruded.layers.splice(at, 2, {
  id: "building-3d", type: "fill-extrusion", source: "gsi", "source-layer": "building",
  paint: { "fill-extrusion-color": "#e3ddd3", "fill-extrusion-height": ["match", ["get", "ftCode"], 3103, 30, 8] },
});
await mkdir(path.join(ROOT, "bench/dist"), { recursive: true });
await writeFile(path.join(ROOT, "bench/dist/query-flat.json"), JSON.stringify(base));
await writeFile(path.join(ROOT, "bench/dist/query-extrusion.json"), JSON.stringify(extruded));

const tokyo = [139.7671, 35.6812];
const views = [
  { name: "flat", style: "query-flat", camera: { center: tokyo, zoom: 15, bearing: 0, pitch: 0 } },
  { name: "turned", style: "query-flat", camera: { center: [139.7645, 35.6795], zoom: 15.6, bearing: 30, pitch: 0 } },
  { name: "tilted", style: "query-flat", camera: { center: tokyo, zoom: 15.3, bearing: -25, pitch: 50 }, tilted: true },
  { name: "extrusion", style: "query-extrusion", camera: { center: tokyo, zoom: 15.5, bearing: -20, pitch: 55 }, tilted: true },
];
const points = [];
for (let y = 60; y < 600; y += 80) for (let x = 50; x < 800; x += 100) points.push([x, y]);
const boxes = [[[300, 200], [500, 400]], [[0, 0], [160, 120]], [[620, 450], [800, 600]], [[390, 290], [410, 310]]];
const asks = [
  ...points.map((p) => ["rendered", p]),
  ...boxes.map((b) => ["rendered", b]),
  ["rendered", null],
  ["rendered", [400, 300], { layers: ["road", "railway", "road-casing"] }],
  ["rendered", [[200, 150], [600, 450]], { filter: ["==", ["get", "ftCode"], 3103] }],
  ["source", ["gsi", { sourceLayer: "road" }]],
  ["source", ["gsi", { sourceLayer: "building", filter: ["==", ["get", "ftCode"], 3103] }]],
];

// Neighbouring extrusions with the same vertices (a building and its outline) in one order.
function sameDepthInOrder(features) {
  const out = [...features];
  const pairs = (c) => (typeof c[0] === "number" ? [String(c)] : c.flatMap(pairs));
  const footprint = (f) => JSON.stringify([...new Set(pairs(f.geometry.coordinates))].sort());
  for (let i = 0; i + 1 < out.length; i++) {
    const [a, b] = [out[i], out[i + 1]];
    if (a.layer === b.layer && a.layer === "building-3d" && footprint(a) === footprint(b) && a.geometry.type > b.geometry.type) {
      [out[i], out[i + 1]] = [b, a];
    }
  }
  return out;
}

const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = [];
let failed = 0;
try {
  for (const v of views) {
    const page = await browser.newPage({ viewport: { width: 800, height: 1200 } });
    page.on("pageerror", (e) => console.log(v.name, "pageerror", e.message));
    await page.goto(`${origin}/bench/query/index.html?style=/bench/dist/${v.style}.json&camera=${encodeURIComponent(JSON.stringify(v.camera))}`);
    await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    for (const [kind, geometry, options] of asks) {
      if (v.tilted && (kind === "source" || geometry === null)) continue;
      const r = await page.evaluate(([k, g, o]) => window.__query(k, g, o), [kind, geometry, options]);
      // A source query lists each tile's features in an order of tiles MapLibre
      // does not define, so it is compared as a multiset.
      const key = (xs) => (kind === "source" ? xs.map((f) => JSON.stringify(f)).sort() : sameDepthInOrder(xs).map((f) => JSON.stringify(f)));
      const a = key(r.mbmap);
      const b = key(r.maplibre);
      const first = a.findIndex((s, i) => s !== b[i]);
      const same = a.length === b.length && first < 0;
      if (!same) failed++;
      results.push({
        view: v.name, kind, geometry, options, same, mbmap: a.length, maplibre: b.length,
        ...(same ? {} : { firstDifference: first < 0 ? a.length : first, mbmapAt: a[first]?.slice(0, 300), maplibreAt: b[first]?.slice(0, 300) }),
      });
    }
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}
const summary = { asks: results.length, identical: results.length - failed, features: results.reduce((n, r) => n + r.maplibre, 0) };
await writeFile(path.join(ROOT, "bench/results/query-golden.json"), JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, summary, results }, null, 2) + "\n");
console.log(JSON.stringify(summary));
for (const r of results.filter((r) => !r.same)) console.log(JSON.stringify(r));
if (failed) process.exit(1);
