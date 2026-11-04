// The OpenMapTiles-schema public styles (style/public-styles.mjs) drawn by mbmap and MapLibre GL JS
// 6.16.0 on OpenFreeMap's tiles of the GSI area (bench/fixtures/ofm-planet, z14) with their own
// sprites, pixel by pixel; labels are compared by labels:golden, so symbol layers are left out, and
// the low-zoom shaded-relief raster is too. node style/public.mjs [--scene=name] [--shots=dir];
// writes bench/results/style-public.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { compareScenes } from "./compare.mjs";
import { loadPublicStyle } from "./public-styles.mjs";

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1];
const TILES = { type: "vector", tiles: ["{origin}/bench/fixtures/ofm-planet/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14 };
// Each style's sprite in bench/fixtures/sprites/ (maptiler-basic draws no images).
const STYLES = { "osm-bright": "osm-bright", positron: "positron", "dark-matter": "dark-matter", "maptiler-basic": "maptiler-basic",
  "ofm-liberty": "ofm", "ofm-bright": "ofm", "ofm-positron": "ofm" };
const CAMERAS = {
  tokyo: { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 },
  turned: { center: [139.764, 35.6795], zoom: 14.6, bearing: 25, pitch: 0 },
};
// Measured in the cloud (SwiftShader) and set just above, with what mbmap lacks there.
const DASHES = "thin dashed paths past the source's maxzoom: MapLibre lays the tile out again (sharp corners split by overscaling)";
const LIMITS = {
  "osm-bright-tokyo": { mean: 0.08, p99: 1, gap: DASHES },
  "maptiler-basic-tokyo": { mean: 0.13, p99: 4, gap: DASHES },
  "maptiler-basic-turned": { mean: 0.08, p99: 2, gap: "thin dashed paths with bevel joins" },
  "ofm-liberty-tokyo": { mean: 0.12, p99: 2, gap: DASHES },
  "ofm-liberty-turned": { mean: 0.12, p99: 2, gap: "thin dashed paths" },
};

function local(style, sprite) {
  const kept = new Set(Object.entries(style.sources).filter(([, s]) => s.type === "vector").map(([id]) => id));
  const { glyphs, ...rest } = style;
  return {
    ...rest,
    sprite: `{origin}/bench/fixtures/sprites/${sprite}/sprite`,
    sources: Object.fromEntries([...kept].map((id) => [id, TILES])),
    layers: style.layers.filter((l) => l.type !== "symbol" && (l.type === "background" || kept.has(l.source))),
  };
}

const scenes = {};
for (const [name, sprite] of Object.entries(STYLES)) {
  const style = local(await loadPublicStyle(name), sprite);
  for (const [view, camera] of Object.entries(CAMERAS)) {
    const key = `${name}-${view}`;
    const { gap, ...limits } = LIMITS[key] ?? { mean: 0.05, p99: 1 };
    scenes[key] = { style, camera, limits, ...(gap ? { gap } : {}) };
  }
}
const only = arg("scene");
const results = await compareScenes(scenes, { only, shots: arg("shots"), dir: "bench/dist/style-public" });
if (!only) await writeFile(path.join(ROOT, "bench/results/style-public.json"), `${JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600", tiles: "openfreemap 20261101_080013_pt" }, results }, null, 2)}\n`);
