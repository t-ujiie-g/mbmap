// route.wasm vs geojson-path-finder 2.1.0 on jittered grid networks and GSI roads: the same path (every
// coordinate) and weight (Object.is) for random pairs of vertices, and no path where it finds none.
// Usage: node route/golden.mjs [--tiles=N] [--queries=N]; writes bench/results/route-golden.json.
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import pathFinder from "geojson-path-finder";
import { hostNumber } from "../../wasmio/js/host.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const PathFinder = pathFinder.default ?? pathFinder;
const TILES = Number(arg("tiles", 4));
const QUERIES = Number(arg("queries", 200));

let a;
const { instance: ai } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm")),
  { Math, host: { number: hostNumber(() => a.memory) } },
);
a = ai.exports;
const { instance: ri } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/route_worker/route_worker.wasm")), { Math });
const r = ri.exports;
const decoder = new TextDecoder();
const put = (e, bytes) => {
  const at = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
};
const out = (e, n) => {
  if (n < 0) throw new Error(decoder.decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
};
function network(fc, tolerance) {
  put(a, new TextEncoder().encode(JSON.stringify(fc)));
  const id = a.load();
  put(r, out(a, a.table_out(id)));
  a.dispose(id);
  const handle = r.network_new(tolerance);
  if (handle < 0) throw new Error(decoder.decode(out(r, -handle)));
  return handle;
}
function route(handle, from, to) {
  const v = new Float64Array(out(r, r.network_path(handle, ...from, ...to) * 8).buffer);
  return v.length ? { path: Array.from({ length: (v.length - 1) / 2 }, (_, i) => [v[1 + i * 2], v[2 + i * 2]]), weight: v[0] } : null;
}

const results = {};
const failures = [];
const same = (x, y) => (Array.isArray(x) ? Array.isArray(y) && x.length === y.length && x.every((v, i) => same(v, y[i])) : x && typeof x === "object" ? y && typeof y === "object" && same(x.path, y.path) && Object.is(x.weight, y.weight) : Object.is(x, y));
function check(group, label, want, got) {
  const s = (results[group] ??= { cases: 0, identical: 0, paths: 0 });
  s.cases++;
  if (want) s.paths++;
  if (same(want, got)) s.identical++;
  else if (failures.length < 20) failures.push({ group, label, want: JSON.stringify(want)?.slice(0, 300), got: JSON.stringify(got)?.slice(0, 300) });
}

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(196);
const line = (coordinates) => ({ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates } });

// Queries between random vertices of the network (and a few points off it).
function compare(group, fc, tolerance) {
  const finder = new PathFinder(JSON.parse(JSON.stringify(fc)), { tolerance });
  const handle = network(fc, tolerance);
  const vertices = fc.features.flatMap((f) => f.geometry.coordinates);
  for (let q = 0; q < QUERIES; q++) {
    const pick = () => (rand() < 0.05 ? [139 + rand(), 35 + rand()] : vertices[Math.floor(rand() * vertices.length)]);
    const [from, to] = [pick(), pick()];
    const want = finder.findPath({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: from } }, { type: "Feature", properties: {}, geometry: { type: "Point", coordinates: to } });
    check(group, `${from} -> ${to}`, want ? { path: want.path, weight: want.weight } : null, route(handle, from, to));
  }
  r.network_dispose(handle);
}

// Jittered grids: rows and columns as lines, vertices off the grid by up to a tenth of a cell.
for (const [n, cell, tolerance] of [[10, 0.01, 1e-5], [20, 0.002, 1e-5], [15, 0.005, 1e-4]]) {
  const at = Array.from({ length: n }, (_, i) => Array.from({ length: n }, (_, j) => [139.7 + j * cell + (rand() - 0.5) * cell * 0.2, 35.6 + i * cell + (rand() - 0.5) * cell * 0.2]));
  const features = [...at.map((row) => line(row)), ...at[0].map((_, j) => line(at.map((row) => row[j])))];
  compare("grid", { type: "FeatureCollection", features }, tolerance);
}

// GSI roads, each tile's road lines.
const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
let tiles = 0;
for (const x of (await readdir(dir)).sort()) {
  for (const f of (await readdir(path.join(dir, x))).sort()) {
    if (tiles++ >= TILES) break;
    const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
    const l = tile.layers.road;
    const features = [];
    for (let i = 0; l && i < l.length; i++) {
      const g = l.feature(i).toGeoJSON(Number(x), parseInt(f), 14).geometry;
      if (g.type === "LineString") features.push(line(g.coordinates));
      else if (g.type === "MultiLineString") for (const c of g.coordinates) features.push(line(c));
    }
    compare("gsi roads", { type: "FeatureCollection", features }, 1e-5);
  }
}

console.table(results);
for (const f of failures.slice(0, 10)) console.log(JSON.stringify(f));
const ok = failures.length === 0;
await writeFile(path.join(ROOT, "bench/results/route-golden.json"), JSON.stringify({ tiles: TILES, queries: QUERIES, results, failures, ok }, null, 2) + "\n");
console.log(ok ? "all identical" : `${failures.length} differ`);
process.exit(ok ? 0 : 1);
