// ArcGIS VectorTileServer styles made absolute by mbmap/services' arcgisVectorStyle, drawn by mbmap
// and MapLibre GL JS 6.16.0 from the live service, pixel by pixel; symbol layers left out as in
// style:public. Writes bench/results/services-style.json; Node needs NODE_USE_ENV_PROXY=1 behind a proxy.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { arcgisVectorStyle } from "../../npm/src/services/arcgis.ts";
import { compareScenes } from "../style/compare.mjs";
import { arg } from "../lib/args.mjs";
import { ROOT } from "../lib/root.mjs";

const SERVICES = {
  "world-basemap-v2": "https://basemaps.arcgis.com/arcgis/rest/services/World_Basemap_v2/VectorTileServer",
};
const CAMERAS = {
  tokyo12: { center: [139.7671, 35.6812], zoom: 12, bearing: 0, pitch: 0 },
  tokyo15: { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 },
  turned: { center: [139.764, 35.6795], zoom: 14.6, bearing: 25, pitch: 0 },
  japan: { center: [137.5, 36.5], zoom: 4.5, bearing: 0, pitch: 0 },
};
// Measured in the cloud (SwiftShader) and set just above, with what differs there.
const EXTENT = "tiles of extent 8192 (Esri's at z15 here) quantized to mbmap's TILE_EXTENT 4096 (VISION §4-2): edges move by up to 1/16 px";
const THIN = "thin road and coast lines at a fractional zoom";
const LIMITS = {
  "world-basemap-v2-tokyo12": { mean: 0.1, p99: 2, gap: THIN },
  "world-basemap-v2-tokyo15": { mean: 0.25, p99: 5, gap: EXTENT },
  "world-basemap-v2-japan": { mean: 0.13, p99: 3, gap: THIN },
};

const json = async (url) => {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return res.json();
};

const scenes = {};
const styles = [];
for (const [name, url] of Object.entries(SERVICES)) {
  const service = await json(`${url}?f=json`);
  const styleUrl = `${url}/${service.defaultStyles}/root.json`;
  const full = arcgisVectorStyle(await json(styleUrl), styleUrl, service, url);
  const types = {};
  for (const l of full.layers) types[l.type] = (types[l.type] ?? 0) + 1;
  styles.push({ name, url, layers: types, source: full.sources.esri });
  const style = { ...full, layers: full.layers.filter((l) => l.type !== "symbol") };
  for (const [view, camera] of Object.entries(CAMERAS)) {
    const key = `${name}-${view}`;
    const { gap, ...limits } = LIMITS[key] ?? { mean: 0.05, p99: 1 };
    scenes[key] = { style, camera, limits, ...(gap ? { gap } : {}) };
  }
}
const only = arg("scene");
const results = await compareScenes(scenes, { only, shots: arg("shots"), dir: "bench/dist/services-style" });
if (!only) {
  await writeFile(path.join(ROOT, "bench/results/services-style.json"), `${JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600", date: new Date().toISOString().slice(0, 10) }, styles, results }, null, 2)}\n`);
}
