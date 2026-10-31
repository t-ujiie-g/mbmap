// Golden test: tiler must cut every tile in range exactly as geojson-vt does
// (js build in full, wasm-gc by hash), with geojson-vt's defaults and
// MapLibre's settings, wrapping or not. Usage: node geojson/golden.mjs
import { readFile } from "node:fs/promises";
import { GeoJSONVT } from "@maplibre/geojson-vt";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { makeGeoJSONFixtures } from "./fixtures.mjs";

const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);

// geojson_tile_hash of a flattened tile, in JS.
function hash(flat) {
  if (flat.length === 0) return 0;
  let h = 0x811c9dc5 | 0;
  for (const v of flat) h = Math.imul(h ^ v, 0x01000193);
  return h;
}
const files = await makeGeoJSONFixtures();

export const OPTION_SETS = {
  defaults: { maxZoom: 14, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 64, wrap: true },
  // MapLibre's GeoJSON source: maxzoom 18, buffer 128 and tolerance 0.375
  // of a 512 px tile, in 4096-unit tiles.
  maplibre: { maxZoom: 18, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 1024, wrap: true },
  noWrap: { maxZoom: 14, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 64, wrap: false },
};

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

// Tiles from z0 up to `maxZ` over the data's extent (a few rings around it),
// plus every tile of z0-3 for the world data.
function tilesFor(bbox, maxZ) {
  const out = [];
  for (let z = 0; z <= maxZ; z++) {
    const n = 2 ** z;
    const tx = (lng) => Math.floor(((lng + 180) / 360) * n);
    const ty = (lat) => {
      const s = Math.sin((lat * Math.PI) / 180);
      return Math.floor((0.5 - (0.25 * Math.log((1 + s) / (1 - s))) / Math.PI) * n);
    };
    const [x0, x1] = [tx(bbox[0]) - 1, tx(bbox[2]) + 1];
    const [y0, y1] = [Math.max(0, ty(bbox[3]) - 1), Math.min(n - 1, ty(bbox[1]) + 1)];
    if ((x1 - x0 + 1) * (y1 - y0 + 1) > 400) continue;
    for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) out.push([z, x, y]);
  }
  return out;
}

function bboxOf(data) {
  const b = [Infinity, Infinity, -Infinity, -Infinity];
  const visit = (c) => {
    if (typeof c[0] === "number") {
      b[0] = Math.min(b[0], c[0]); b[1] = Math.min(b[1], c[1]); b[2] = Math.max(b[2], c[0]); b[3] = Math.max(b[3], c[1]);
    } else c.forEach(visit);
  };
  for (const f of data.features) if (f.geometry) visit(f.geometry.coordinates);
  return [Math.max(-180, b[0]), Math.max(-85, b[1]), Math.min(180, b[2]), Math.min(85, b[3])];
}

let failures = 0, compared = 0, featuresCompared = 0;
for (const [name, file] of Object.entries(files)) {
  const text = await readFile(file);
  const data = JSON.parse(text.toString());
  for (const [setName, o] of Object.entries(OPTION_SETS)) {
    const ref = new GeoJSONVT(data, { ...o, generateId: true });
    const n = mbt.geojson_tiler(new Uint8Array(text), o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, o.wrap);
    const addr = gc.copyIn(new Uint8Array(text));
    const m = gc.exports.geojson_tiler_mem(addr, text.length, o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, o.wrap ? 1 : 0);
    if (n !== data.features.length || m !== n) {
      console.log(`${name}/${setName}: read ${n} (js) and ${m} (wasm-gc) features, expected ${data.features.length}`);
      failures++;
      continue;
    }
    const tiles = name === "world" ? tilesFor([-180, -85, 180, 85], 3) : tilesFor(bboxOf(data), Math.min(o.maxZoom, 17));
    for (const [z, x, y] of tiles) {
      const a = flatten(ref.getTile(z, x, y));
      const b = [...mbt.geojson_tile(z, x, y)];
      compared++;
      featuresCompared += a[0] ?? 0;
      const same = a.length === b.length && a.every((v, i) => v === b[i]) && gc.exports.geojson_tile_hash(z, x, y) === hash(a);
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
