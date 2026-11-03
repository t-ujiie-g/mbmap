// Label placement vs MapLibre GL JS 6.16.0 in Chromium (same style, tiles, camera, local "sans-serif"
// glyphs): the same labels shown, each at the same anchor. Usage: node labels/golden.mjs [--scene=name]
// [--debug=px]; writes bench/results/labels-golden.json. Needs `npm --prefix npm run build`.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1];
// How far a glyph along a line may lie from MapLibre's (CSS px) and turn from it (radians).
const GLYPH_TOLERANCE = 0.5;
const ANGLE_TOLERANCE = 0.01;
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
  ...contourScenes(),
  ...iconScenes(),
};

// Icons (page.mjs draws the images: dot, box, pin at 2x, an SDF ring; "nope" is missing): GSI
// symbols by their code, alone or under a layer of labels, and labels with icons.
function iconScenes() {
  const byCode = ["match", ["get", "ftCode"], 3211, "dot", 3212, "box", 3213, "pin", 3214, "nope", 3215, "box", "ring"];
  const symbols = (id, layout = {}, filter) => ({
    id, type: "symbol", source: "gsi", "source-layer": "symbol", ...(filter ? { filter } : {}),
    layout: { "icon-image": byCode, ...layout },
  });
  const withIcon = (layout) => label("l", { "text-max-width": 8, "icon-image": "dot", ...layout });
  const POI = { "text-anchor": "top", "text-offset": [0, 0.8] };
  return {
    icons: { style: style(symbols("s")), camera: { center: tokyo, zoom: 15.3 } },
    "icons-turned": {
      style: style(symbols("s", { "icon-rotate": 20, "icon-anchor": "bottom", "icon-offset": [2, -3], "icon-padding": [1, 4], "icon-size": 1.3 })),
      camera: { center: [139.7645, 35.6795], zoom: 15.4, bearing: 30 },
    },
    "icons-tilted": {
      style: style(symbols("s", { "icon-rotation-alignment": "map", "icon-size": ["match", ["get", "ftCode"], 3212, 2, 1] })),
      camera: { center: tokyo, zoom: 15.2, bearing: -20, pitch: 50 },
    },
    "icons-and-text": { style: style(withIcon(POI)), camera: { center: tokyo, zoom: 15 } },
    "icons-text-optional": { style: style(withIcon({ ...POI, "text-optional": true })), camera: { center: tokyo, zoom: 14.7 } },
    "icons-icon-optional": {
      style: style(withIcon({ ...POI, "icon-optional": true, "icon-image": ["match", ["get", "annoCtg"], 412, "nope", "box"], "icon-size": 1.5 })),
      camera: { center: tokyo, zoom: 14.7 },
    },
    "icons-overlap": {
      style: style(
        symbols("under", { "icon-ignore-placement": true, "icon-allow-overlap": true }),
        withIcon({ ...POI, "icon-allow-overlap": true, "icon-image": "pin" }),
      ),
      camera: { center: tokyo, zoom: 14.8 },
    },
    "icons-variable": {
      style: style(withIcon({ ...VARIABLE, "icon-image": "box" })),
      camera: { center: [139.7645, 35.6795], zoom: 15.4, bearing: 30 },
    },
    "icons-fit": {
      style: style(withIcon({ ...VARIABLE, "icon-image": "box", "icon-text-fit": "both", "icon-text-fit-padding": [2, 4, 2, 4] })),
      camera: { center: tokyo, zoom: 15 },
    },
    "icons-fit-width": {
      style: style(withIcon({ "icon-image": "pin", "icon-text-fit": "width", "icon-text-fit-padding": [0, 3, 0, 3], "icon-allow-overlap": true })),
      camera: { center: tokyo, zoom: 15.3 },
    },
  };
}

// GSI contours (west of the fixtures) labeled with their heights along the lines.
function contourScenes() {
  const west = [139.702, 35.664];
  const contours = (layout = {}) => ({
    id: "c", type: "symbol", source: "gsi", "source-layer": "contour",
    layout: { "symbol-placement": "line", "text-field": "{alti}", "text-font": ["sans-serif"], "text-size": 11, ...layout },
    paint: { "text-color": "#8a6d3b" },
  });
  return {
    contours: { style: style(contours()), camera: { center: west, zoom: 14.5 }, along: true },
    "contours-turned": { style: style(contours()), camera: { center: west, zoom: 14.7, bearing: 40 }, along: true },
    "contours-tilted": { style: style(contours()), camera: { center: west, zoom: 14.6, bearing: -15, pitch: 45 }, along: true },
    "contours-deeper": { style: style(contours({ "symbol-spacing": 150 })), camera: { center: west, zoom: 15.4 }, along: true },
    "contours-center": { style: style(contours({ "symbol-placement": "line-center", "text-max-angle": 30 })), camera: { center: west, zoom: 14.5 }, along: true },
    "contours-upright": { style: style(contours({ "text-keep-upright": false, "text-size": 14 })), camera: { center: west, zoom: 14.8, bearing: 160 }, along: true },
    "contours-and-points": {
      style: style(contours(), label("l", { "text-max-width": 8 })),
      camera: { center: west, zoom: 14.8 }, along: true,
    },
  };
}

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
    const anchors = both
      .filter((l) => l.anchor !== theirs.get(l.key).anchor || l.text !== theirs.get(l.key).text || l.icon !== theirs.get(l.key).icon)
      .map((l) => `${l.key}: ${l.anchor} ${l.text} ${l.icon} vs ${theirs.get(l.key).anchor} ${theirs.get(l.key).text} ${theirs.get(l.key).icon}`);
    // How far the boxes the labels both placed put in the grid lie apart, in CSS px.
    const diff = (l) => Math.max(0, ...l.box.flatMap((b, k) => {
      const t = theirs.get(l.key).box[k];
      return t ? b.map((v, i) => Math.abs(v - t[i])) : [];
    }));
    const boxDiff = Math.max(0, ...both.map(diff));
    // Along lines: how far each glyph lies from MapLibre's on screen (px) and turns from it (radians).
    const hidden = (g) => !Number.isFinite(g[0]) || Math.abs(g[0]) > 1e6;
    let glyphDiff = 0;
    let angleDiff = 0;
    let glyphCount = 0;
    for (const l of both.filter((l) => l.glyphs)) {
      const theirGlyphs = theirs.get(l.key).glyphs ?? [];
      l.glyphs.forEach((g, k) => {
        const t = theirGlyphs[k];
        if (!t || hidden(g) !== hidden(t)) glyphDiff = Infinity;
        else if (!hidden(g)) {
          glyphCount++;
          glyphDiff = Math.max(glyphDiff, Math.hypot(g[0] - t[0], g[1] - t[1]));
          const turn = Math.abs(g[2] - t[2]) % (2 * Math.PI);
          angleDiff = Math.max(angleDiff, Math.min(turn, 2 * Math.PI - turn));
        }
      });
    }
    if (arg("debug")) {
      const tiles = (ls) => [...new Set(ls.map((l) => l.key.split(" ")[1]))].sort().join(" ");
      console.log("tiles", tiles(mbmap), "|", tiles(maplibre));
      for (const l of both) {
        if (diff(l) > Number(arg("debug"))) console.log(l.key, l.anchor, theirs.get(l.key).anchor, JSON.stringify(l.box), JSON.stringify(theirs.get(l.key).box));
      }
    }
    const same = missing.length === 0 && extra.length === 0 && anchors.length === 0 && maplibre.length > 0 &&
      glyphDiff <= GLYPH_TOLERANCE && angleDiff <= ANGLE_TOLERANCE;
    if (!same) failed++;
    results.push({
      scene: name, same, maplibre: maplibre.length, mbmap: mbmap.length,
      anchored: both.filter((l) => l.anchor !== null && l.anchor !== "top").length, icons: both.filter((l) => l.icon).length,
      boxDiff: Math.round(boxDiff * 1000) / 1000,
      ...(scene.along ? { glyphs: glyphCount, glyphDiff: Math.round(glyphDiff * 1000) / 1000, angleDiff: Math.round(angleDiff * 1e6) / 1e6 } : {}),
      ...(same ? {} : {
        missing: missing.slice(0, 10).map((k) => `${k} ${JSON.stringify(theirs.get(k).box.map((b) => b.map(Math.round)))}`),
        extra: extra.slice(0, 10).map((k) => `${k} ${JSON.stringify(ours.get(k).box.map((b) => b.map(Math.round)))}`),
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
