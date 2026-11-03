// Golden test: tiler must cut every tile in range exactly as geojson-vt does
// (js build in full, wasm-gc by hash), with geojson-vt's defaults and
// MapLibre's settings, wrapping or not, and with line metrics (where each line
// feature lies along its line). Usage: node geojson/golden.mjs
import { readFile } from "node:fs/promises";
import { GeoJSONVT } from "@maplibre/geojson-vt";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { bboxOf, makeGeoJSONFixtures, tilesFor } from "./fixtures.mjs";

const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);

// geojson_tile_hash of a flattened tile, in JS.
function hash(flat) {
  if (flat.length === 0) return 0;
  let h = 0x811c9dc5 | 0;
  for (const v of flat) h = Math.imul(h ^ v, 0x01000193);
  return h;
}
const files = await makeGeoJSONFixtures();

// `maplibre` is MapLibre's GeoJSON source: maxzoom 18, buffer 128 and
// tolerance 0.375 of a 512 px tile, in 4096-unit tiles.
export const OPTION_SETS = {
  defaults: { maxZoom: 14, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 64, wrap: true },
  maplibre: { maxZoom: 18, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 1024, wrap: true },
  noWrap: { maxZoom: 14, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 64, wrap: false },
  lineMetrics: { maxZoom: 18, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 1024, wrap: true, lineMetrics: true },
};

// The reference tile's line metrics as `geojson_tile_clips` gives them, and their hash.
function clipsOf(tile) {
  if (!tile) return [];
  return tile.features.flatMap((f) => {
    const t = f.tags ?? {};
    return f.type === 2 && "geojsonvt_clip_start" in t ? [t.geojsonvt_clip_start, t.geojsonvt_clip_end] : [NaN, NaN];
  });
}
function clipsHash(values) {
  if (values.length === 0) return 0x811c9dc5 | 0;
  const bits = new Int32Array(new Float64Array(values).buffer);
  let h = 0x811c9dc5 | 0;
  for (const v of bits) h = Math.imul(h ^ v, 0x01000193);
  return h;
}

// The reference tile in the export's flattened form (see geojson_tile).
function flatten(tile) {
  if (!tile) return [];
  const head = [tile.features.length];
  const xy = [];
  for (const f of tile.features) {
    const rings = f.type === 1 ? [f.geometry] : f.geometry;
    head.push(f.type, f.id, rings.length);
    for (const r of rings) {
      head.push(r.length);
      for (const [x, y] of r) xy.push(x, y);
    }
  }
  return head.concat(xy);
}

let failures = 0, compared = 0, featuresCompared = 0;
for (const [name, file] of Object.entries(files)) {
  const text = await readFile(file);
  const data = JSON.parse(text.toString());
  for (const [setName, o] of Object.entries(OPTION_SETS)) {
    const ref = new GeoJSONVT(data, { ...o, generateId: true });
    const n = mbt.geojson_tiler(new Uint8Array(text), o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, o.wrap, !!o.lineMetrics);
    const addr = gc.copyIn(new Uint8Array(text));
    const m = gc.exports.geojson_tiler_mem(addr, text.length, o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, o.wrap ? 1 : 0, o.lineMetrics ? 1 : 0);
    if (n !== data.features.length || m !== n) {
      console.log(`${name}/${setName}: read ${n} (js) and ${m} (wasm-gc) features, expected ${data.features.length}`);
      failures++;
      continue;
    }
    const tiles = name === "world" ? tilesFor([-180, -85, 180, 85], 3) : tilesFor(bboxOf(data), Math.min(o.maxZoom, 17));
    for (const [z, x, y] of tiles) {
      const t = ref.getTile(z, x, y);
      const a = flatten(t);
      const b = [...mbt.geojson_tile(z, x, y)];
      compared++;
      featuresCompared += a[0] ?? 0;
      const ca = o.lineMetrics ? clipsOf(t) : [];
      const cb = [...mbt.geojson_tile_clips(z, x, y)];
      const sameClips = ca.length === cb.length && ca.every((v, i) => Object.is(v, cb[i])) &&
        gc.exports.geojson_tile_clips_hash(z, x, y) === clipsHash(ca);
      const same = sameClips && a.length === b.length && a.every((v, i) => v === b[i]) && gc.exports.geojson_tile_hash(z, x, y) === hash(a);
      if (!same) {
        if (failures < 5) {
          const i = a.findIndex((v, k) => v !== b[k]);
          console.log(`${name}/${setName} ${z}/${x}/${y}: differs at ${i}: ${a.slice(i, i + 6)} vs ${b.slice(i, i + 6)} (lengths ${a.length}, ${b.length})`);
        }
        failures++;
      }
    }
  }
}
console.log(`${compared} tiles, ${featuresCompared} features compared (js in full, wasm-gc by hash); ${failures} differ`);
if (failures > 0) process.exit(1);
