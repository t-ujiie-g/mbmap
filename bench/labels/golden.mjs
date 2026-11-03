// Label placement vs MapLibre GL JS 6.16.0 in Chromium (same style, tiles, camera, local "sans-serif"
// glyphs): the same labels shown, each at the same anchor. Usage: node labels/golden.mjs [--scene=name]
// [--debug=px]; writes bench/results/labels-golden.json. Needs `npm --prefix npm run build`.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1];
const only = arg("scene");
const tokyo = [139.7671, 35.6812];
const source = { type: "vector", tiles: ["{origin}/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14 };
const style = (...layers) => ({ version: 8, sources: { gsi: source }, layers: [{ id: "bg", type: "background", paint: { "background-color": "#ffffff" } }, ...layers] });
const label = (id, layout, filter) => ({
  id, type: "symbol", source: "gsi", "source-layer": "label", ...(filter ? { filter } : {}),
  layout: { "text-field": "{knj}", "text-font": ["sans-serif"], "text-size": 12, ...layout },
  paint: { "text-color": "#333333" },
});
const VARIABLE = { "text-variable-anchor": ["top", "bottom", "left", "right"], "text-radial-offset": 0.5, "text-justify": "auto" };
const SCENES = {
  fixed: { style: style(label("l", { "text-max-width": 8 })), camera: { center: tokyo, zoom: 15 } },
  "fixed-turned": { style: style(label("l", { "text-max-width": 8 })), camera: { center: [139.7645, 35.6795], zoom: 15.4, bearing: 30 } },
  "fixed-tilted": { style: style(label("l", { "text-max-width": 8 })), camera: { center: tokyo, zoom: 15.2, bearing: -20, pitch: 50 } },
  radial: { style: style(label("l", VARIABLE)), camera: { center: tokyo, zoom: 15 } },
  "radial-turned": { style: style(label("l", VARIABLE)), camera: { center: [139.7645, 35.6795], zoom: 15.4, bearing: 30 } },
  "radial-tilted": { style: style(label("l", VARIABLE)), camera: { center: tokyo, zoom: 15.2, bearing: -20, pitch: 50 } },
  "offset-sorted": {
    style: style(label("l", {
      "text-variable-anchor": ["bottom-left", "top-right", "left", "right", "top", "bottom"], "text-offset": [0.4, 0.6],
      "text-max-width": 4, "text-justify": "auto", "symbol-sort-key": ["get", "annoCtg"],
    })),
    camera: { center: tokyo, zoom: 15 },
  },
  "anchor-offset-two-layers": {
    style: style(
      label("under", { "text-variable-anchor-offset": ["top", [0, 0.5], "bottom", [0, -0.5], "left", [0.6, 0], "right", [-0.6, 0]], "text-padding": 4 }, ["!=", ["get", "annoCtg"], 412]),
      label("over", { "text-size": 14, "text-allow-overlap": false }, ["==", ["get", "annoCtg"], 412]),
    ),
    camera: { center: tokyo, zoom: 15.6 },
  },
  "overlap-anchors": {
    style: style(
      label("allowed", { ...VARIABLE, "text-allow-overlap": true }, ["==", ["get", "annoCtg"], 412]),
      label("rest", VARIABLE, ["!=", ["get", "annoCtg"], 412]),
    ),
    camera: { center: tokyo, zoom: 14.6 },
  },
  "basic-labels": {
    style: style(
      label("label", { "text-max-width": 8, "symbol-sort-key": ["get", "annoCtg"] }, ["!", ["in", ["get", "arrng"], ["literal", [2, 4]]]]),
      label("label-vertical", { "text-max-width": 8, "text-writing-mode": ["vertical"], "symbol-sort-key": ["get", "annoCtg"] }, ["in", ["get", "arrng"], ["literal", [2, 4]]]),
    ),
    camera: { center: tokyo, zoom: 15 },
  },
};

await mkdir(path.join(ROOT, "bench/dist/labels"), { recursive: true });
const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = [];
let failed = 0;
try {
  for (const [name, scene] of Object.entries(SCENES)) {
    if (only && name !== only) continue;
    const file = `bench/dist/labels/${name}.json`;
    await writeFile(path.join(ROOT, file), JSON.stringify(scene.style));
    const page = await browser.newPage({ viewport: { width: 800, height: 1200 } });
    page.on("pageerror", (e) => console.log(name, "pageerror", e.message));
    await page.goto(`${origin}/bench/labels/index.html?style=/${file}&camera=${encodeURIComponent(JSON.stringify(scene.camera))}`);
    await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    const { mbmap, maplibre } = await page.evaluate(() => window.__placed());
    await page.close();
    const theirs = new Map(maplibre.map((l) => [l.key, l]));
    const ours = new Map(mbmap.map((l) => [l.key, l]));
    const missing = maplibre.filter((l) => !ours.has(l.key)).map((l) => l.key);
    const extra = mbmap.filter((l) => !theirs.has(l.key)).map((l) => l.key);
    const both = mbmap.filter((l) => theirs.has(l.key));
    const anchors = both.filter((l) => l.anchor !== theirs.get(l.key).anchor).map((l) => `${l.key}: ${l.anchor} vs ${theirs.get(l.key).anchor}`);
    // How far the boxes of the labels both placed lie apart, in CSS px.
    const boxDiff = Math.max(0, ...both.map((l) => {
      const b = theirs.get(l.key).box;
      return b ? Math.max(...l.box.map((v, i) => Math.abs(v - b[i]))) : 0;
    }));
    if (arg("debug")) {
      const tiles = (ls) => [...new Set(ls.map((l) => l.key.split(" ")[1]))].sort().join(" ");
      console.log("tiles", tiles(mbmap), "|", tiles(maplibre));
      for (const l of both) {
        const b = theirs.get(l.key).box;
        if (b && l.box.some((v, i) => Math.abs(v - b[i]) > Number(arg("debug")))) console.log(l.key, l.anchor, theirs.get(l.key).anchor, l.box.map((v) => v.toFixed(3)), b.map((v) => v.toFixed(3)));
      }
    }
    const same = missing.length === 0 && extra.length === 0 && anchors.length === 0 && maplibre.length > 0;
    if (!same) failed++;
    results.push({
      scene: name, same, maplibre: maplibre.length, mbmap: mbmap.length,
      anchored: both.filter((l) => l.anchor !== null && l.anchor !== "top").length, boxDiff: Math.round(boxDiff * 1000) / 1000,
      ...(same ? {} : {
        missing: missing.slice(0, 10).map((k) => `${k} ${theirs.get(k).box?.map(Math.round)}`),
        extra: extra.slice(0, 10).map((k) => `${k} ${ours.get(k).box.map(Math.round)}`),
        anchors: anchors.slice(0, 10),
      }),
    });
  }
} finally {
  await browser.close();
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/labels-golden.json"), JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
if (failed) process.exit(1);
