// GeoJSON to tiles: @maplibre/geojson-vt (decode + JSON.parse, index, tiles)
// against the wasm-gc build of mbmap's formats + tiler (copy into linear
// memory + read, index, tiles), with MapLibre's GeoJSON source settings.
// "tiles" cuts every tile over the data from z6 to z16 from a fresh index,
// so each is cut (drilled down) rather than served from the cache.
import { GeoJSONVT } from "@maplibre/geojson-vt";

export const OPTIONS = { maxZoom: 18, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 1024, wrap: true };
export const DATASETS = ["points", "roads", "roads6", "buildings"];

const median = (xs) => [...xs].sort((a, b) => a - b)[xs.length >> 1];

function bboxOf(data) {
  const b = [Infinity, Infinity, -Infinity, -Infinity];
  const visit = (c) => {
    if (typeof c[0] === "number") {
      b[0] = Math.min(b[0], c[0]); b[1] = Math.min(b[1], c[1]); b[2] = Math.max(b[2], c[0]); b[3] = Math.max(b[3], c[1]);
    } else c.forEach(visit);
  };
  for (const f of data.features) if (f.geometry) visit(f.geometry.coordinates);
  return b;
}

function tilesOver(b) {
  const out = [];
  for (let z = 6; z <= 16; z++) {
    const n = 2 ** z;
    const tx = (lng) => Math.floor(((lng + 180) / 360) * n);
    const ty = (lat) => {
      const s = Math.sin((lat * Math.PI) / 180);
      return Math.floor((0.5 - (0.25 * Math.log((1 + s) / (1 - s))) / Math.PI) * n);
    };
    for (let x = tx(b[0]); x <= tx(b[2]); x++) for (let y = ty(b[3]); y <= ty(b[1]); y++) out.push([z, x, y]);
  }
  return out;
}

export async function runGeoJSONBench(fetchBytes, { gc }, { runs = 5 } = {}) {
  const e = gc.exports;
  const o = OPTIONS;
  const buildMbmap = (bytes) => {
    const addr = gc.copyIn(bytes);
    return e.geojson_tiler_mem(addr, bytes.length, o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, o.wrap ? 1 : 0);
  };
  const time = (f) => {
    f(); // warm-up
    const xs = [];
    for (let i = 0; i < runs; i++) {
      const t0 = performance.now();
      f();
      xs.push(performance.now() - t0);
    }
    return median(xs);
  };
  const timeAfter = (setup, f) => {
    setup(); f();
    const xs = [];
    for (let i = 0; i < runs; i++) {
      setup();
      const t0 = performance.now();
      f();
      xs.push(performance.now() - t0);
    }
    return median(xs);
  };
  const decoder = new TextDecoder();
  const datasets = {};
  for (const name of DATASETS) {
    const bytes = await fetchBytes(`bench/dist/geojson/${name}.geojson`);
    const data = JSON.parse(decoder.decode(bytes));
    const tiles = tilesOver(bboxOf(data));
    let index;
    const js = {
      parseMs: time(() => JSON.parse(decoder.decode(bytes))),
      indexMs: time(() => new GeoJSONVT(data, o)),
      tilesMs: timeAfter(() => { index = new GeoJSONVT(data, o); }, () => { for (const [z, x, y] of tiles) index.getTile(z, x, y); }),
    };
    if (buildMbmap(bytes) !== data.features.length) throw new Error(`${name}: mbmap read a different feature count`);
    const mbmap = {
      readMs: time(() => e.geojson_read_mem(gc.copyIn(bytes), bytes.length)),
      readIndexMs: time(() => buildMbmap(bytes)),
      tilesMs: timeAfter(() => buildMbmap(bytes), () => { for (const [z, x, y] of tiles) e.geojson_tile_size(z, x, y); }),
    };
    js.totalMs = js.parseMs + js.indexMs + js.tilesMs;
    mbmap.totalMs = mbmap.readIndexMs + mbmap.tilesMs;
    datasets[name] = { bytes: bytes.length, features: data.features.length, tiles: tiles.length, js, mbmap };
  }
  return { params: { runs, statistic: "median of runs after one warm-up", options: o }, datasets };
}

export function printGeoJSON(result) {
  const r = (v) => v.toFixed(1);
  console.table(Object.fromEntries(Object.entries(result.datasets).map(([n, d]) => [n, {
    MB: (d.bytes / 1e6).toFixed(1), tiles: d.tiles,
    "js parse": r(d.js.parseMs), "js index": r(d.js.indexMs), "js tiles": r(d.js.tilesMs), "js total": r(d.js.totalMs),
    "mbmap read": r(d.mbmap.readMs), "mbmap read+index": r(d.mbmap.readIndexMs), "mbmap tiles": r(d.mbmap.tilesMs), "mbmap total": r(d.mbmap.totalMs),
  }])));
}
