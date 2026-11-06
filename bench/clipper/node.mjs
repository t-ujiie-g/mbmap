// Dissolve, 10 m buffer and water clip of each fixture tile's buildings: mbmap's wasm modules vs
// Turf.js 7.4.0 (polyclip-ts, JSTS), totals over the first tiles, median of runs.
// Usage: node clipper/node.mjs [--runs=5] [--tiles=5]
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { performance } from "node:perf_hooks";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import buffer from "@turf/buffer";
import union from "@turf/union";
import intersect from "@turf/intersect";
import { hostNumber } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const runs = Number(arg("runs", 5));
const tileCount = Number(arg("tiles", 5));

let a;
const { instance: ai } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm")),
  { Math, host: { number: hostNumber(() => a.memory) } },
);
a = ai.exports;
const { instance: gi } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/geometry_worker/geometry_worker.wasm")), {});
const g = gi.exports;
const put = (e, bytes) => {
  const at = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
};
const out = (e, n) => {
  if (n < 0) throw new Error(new TextDecoder().decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
};
const load = (fc) => {
  put(a, new TextEncoder().encode(JSON.stringify(fc)));
  return a.load();
};
// One geometry call on datasets, as analysis_worker/js/worker.mjs makes it;
// with `geojson`, the result decoded as toGeoJSON() does.
function geometry(ids, call, geojson) {
  const bytes = ids.map((id) => out(a, a.table_out(id)));
  const all = new Uint8Array(bytes.reduce((s, b) => s + b.length, 0));
  let at = 0;
  for (const b of bytes) { all.set(b, at); at += b.length; }
  put(g, all);
  const result = out(g, call(bytes[0].length));
  if (geojson) return tableToGeoJSON(result);
  put(a, result);
  const id = a.load_table();
  a.dispose(id);
  return id;
}

const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
const tiles = [];
for (const x of (await readdir(dir)).sort()) {
  for (const f of (await readdir(path.join(dir, x))).sort()) {
    const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
    const layer = (name) => {
      const l = tile.layers[name];
      const out = [];
      for (let i = 0; l && i < l.length; i++) {
        const feature = l.feature(i).toGeoJSON(Number(x), parseInt(f), 14);
        if (feature.geometry.type === "Polygon" || feature.geometry.type === "MultiPolygon") out.push(feature);
      }
      return { type: "FeatureCollection", features: out };
    };
    if (tiles.length < tileCount) tiles.push({ buildings: layer("building"), water: layer("waterarea") });
  }
}
const boxes = new WeakMap();
function bboxOf(feature) {
  let box = boxes.get(feature);
  if (!box) {
    box = [Infinity, Infinity, -Infinity, -Infinity];
    const rings = feature.geometry.type === "Polygon" ? feature.geometry.coordinates : feature.geometry.coordinates.flat();
    for (const ring of rings) for (const [x, y] of ring) {
      box[0] = Math.min(box[0], x); box[1] = Math.min(box[1], y); box[2] = Math.max(box[2], x); box[3] = Math.max(box[3], y);
    }
    boxes.set(feature, box);
  }
  return box;
}
const overlaps = (p, q) => p[0] <= q[2] && q[0] <= p[2] && p[1] <= q[3] && q[1] <= p[3];
const datasets = tiles.map((t) => ({ buildings: load(t.buildings), water: load(t.water) }));
const total = (fn) => {
  const t0 = performance.now();
  tiles.forEach((t, i) => fn(t, datasets[i]));
  return performance.now() - t0;
};
const med = (xs) => [...xs].sort((p, q) => p - q)[xs.length >> 1];

// Turf's clip meets each building with only the water polygons near it, as mbmap does.
const cases = {
  dissolve: {
    mbmap: (t, d) => geometry([d.buildings], () => g.dissolve()),
    mbmapGeoJSON: (t, d) => geometry([d.buildings], () => g.dissolve(), true),
    turf: (t) => union(t.buildings),
  },
  buffer10m: {
    mbmap: (t, d) => geometry([d.buildings], () => g.buffer(10, 0, 0, 0, 0)),
    mbmapGeoJSON: (t, d) => geometry([d.buildings], () => g.buffer(10, 0, 0, 0, 0), true),
    turf: (t) => buffer(t.buildings, 10, { units: "meters" }),
  },
  clipByWater: {
    mbmap: (t, d) => geometry([d.buildings, d.water], (lenA) => g.overlay(lenA, 0)),
    mbmapGeoJSON: (t, d) => geometry([d.buildings, d.water], (lenA) => g.overlay(lenA, 0), true),
    turf: (t) => t.buildings.features.map((b) => {
      const box = bboxOf(b);
      const near = t.water.features.filter((w) => overlaps(box, bboxOf(w)));
      if (near.length === 0) return null;
      const water = near.length > 1 ? union({ type: "FeatureCollection", features: near }) : near[0];
      return water && intersect({ type: "FeatureCollection", features: [b, water] });
    }),
  },
};
const summary = {};
for (const [name, impls] of Object.entries(cases)) {
  summary[name] = {};
  for (const [impl, fn] of Object.entries(impls)) {
    total(fn); // warm-up
    summary[name][impl] = Math.round(med(Array.from({ length: runs }, () => total(fn))) * 10) / 10;
  }
  console.log(`${name.padEnd(12)} mbmap ${summary[name].mbmap} ms (with GeoJSON out ${summary[name].mbmapGeoJSON} ms), Turf ${summary[name].turf} ms`);
}
const buildings = tiles.reduce((s, t) => s + t.buildings.features.length, 0);
await writeFile(path.join(ROOT, "bench/results/geometry-node.json"), JSON.stringify({
  env: { node: process.version, tiles: tiles.length, buildings },
  params: { runs, statistic: "median of total ms over the tiles" },
  summary,
}, null, 2) + "\n");
