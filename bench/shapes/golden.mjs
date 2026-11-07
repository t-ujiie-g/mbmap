// shapes.wasm vs Turf 7.4.0, concaveman 2.0.0 and d3-delaunay 6.0.6 on GSI features and random points;
// every coordinate and number must be identical (Object.is).
// Usage: node shapes/golden.mjs [--tiles=N]; writes bench/results/shapes-golden.json.
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import simplify from "@turf/simplify";
import convex from "@turf/convex";
import concaveman from "concaveman";
import { Delaunay } from "d3-delaunay";
import { nearestPointOnLine } from "@turf/nearest-point-on-line";
import { lineSlice } from "@turf/line-slice";
import { hostNumber } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const TILES = Number(arg("tiles", 4));

let a;
const { instance: ai } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm")),
  { Math, host: { number: hostNumber(() => a.memory) } },
);
a = ai.exports;
const { instance: si } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/shapes_worker/shapes_worker.wasm")), { Math });
const s = si.exports;
const decoder = new TextDecoder();
const put = (e, bytes) => {
  const at = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
};
const out = (e, n) => {
  if (n < 0) throw new Error(decoder.decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
};
// A FeatureCollection as table bytes, read by analysis.wasm as `load` reads it.
function table(features) {
  put(a, new TextEncoder().encode(JSON.stringify({ type: "FeatureCollection", features })));
  const id = a.load();
  if (id < 0) throw new Error("load failed");
  const bytes = out(a, a.table_out(id));
  a.dispose(id);
  return bytes;
}
// One shapes_worker export over `features`, its table decoded as toGeoJSON() does.
function op(features, name, ...args) {
  put(s, table(features));
  return tableToGeoJSON(out(s, s[name](...args))).features;
}
function nearest(features, x, y) {
  put(s, table(features));
  return new Float64Array(out(s, s.nearest_on_line(x, y) * 8).buffer);
}

const results = {};
const failures = [];
const same = (x, y) => (typeof x === "number" ? Object.is(x, y) : Array.isArray(x) ? Array.isArray(y) && x.length === y.length && x.every((v, i) => same(v, y[i])) : x === y);
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, identical: 0 });
  r.cases++;
  if (same(want, got)) r.identical++;
  else if (failures.length < 30) failures.push({ group, label, want: JSON.stringify(want).slice(0, 400), got: JSON.stringify(got).slice(0, 400) });
}
function attempt(f) {
  try {
    return f();
  } catch (err) {
    return `error: ${err.message}`;
  }
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
const rand = rng(192);
const feature = (geometry) => ({ type: "Feature", properties: {}, geometry });
const points = (n, f) => Array.from({ length: n }, () => feature({ type: "Point", coordinates: f() }));
const anywhere = () => [139.7 + rand() * 0.1, 35.6 + rand() * 0.1];
const onGrid = () => [139.7 + Math.floor(rand() * 8) * 0.01, 35.6 + Math.floor(rand() * 8) * 0.01];

// Delaunay triangles and Voronoi cells of point sets, against d3-delaunay.
function delaunay(group, pts) {
  const coords = pts.map((f) => f.geometry.coordinates);
  const d = Delaunay.from(coords);
  check(`${group} delaunay`, `${coords.length} points`, Array.from(d.trianglePolygons()), attempt(() => op(pts, "delaunay").map((f) => f.geometry.coordinates[0])));
  const box = [139.69, 35.59, 139.81, 35.71];
  const v = d.voronoi(box);
  const cells = attempt(() => op(pts, "voronoi", ...box));
  check(`${group} voronoi`, `${coords.length} points`, coords.map((_, i) => v.cellPolygon(i) ?? null), Array.isArray(cells) ? cells.map((f) => f.geometry?.coordinates?.[0] ?? null) : cells);
}
// Hulls of every vertex, against Turf's convex and concaveman.
function hulls(group, features) {
  const all = [];
  for (const f of features) {
    const flat = (c) => (typeof c[0] === "number" ? all.push(c) : c.forEach(flat));
    flat(f.geometry.coordinates);
  }
  const ring = (fs) => (Array.isArray(fs) ? (fs[0]?.geometry?.coordinates[0] ?? null) : fs);
  check(`${group} convex`, `${all.length} points`, convex({ type: "FeatureCollection", features })?.geometry.coordinates[0] ?? null, ring(attempt(() => op(features, "convex"))));
  for (const [concavity, threshold] of [[1, 0], [2, 0], [3, 0], [2, 0.0005]]) {
    const want = concaveman(all, concavity, threshold);
    check(`${group} concave`, `${all.length} points, ${concavity}, ${threshold}`, want.length >= 4 ? want : null, ring(attempt(() => op(features, "concave", concavity, threshold))));
  }
}

for (let k = 0; k < 30; k++) delaunay("random", points(3 + Math.floor(rand() * 300), anywhere));
for (let k = 0; k < 30; k++) delaunay("grid", points(3 + Math.floor(rand() * 100), onGrid));
delaunay("collinear", points(20, () => [139.7 + rand() * 0.1, 35.6]));
for (let k = 0; k < 20; k++) hulls("random", points(3 + Math.floor(rand() * 500), anywhere));
for (let k = 0; k < 20; k++) hulls("grid", points(3 + Math.floor(rand() * 100), onGrid));

const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
let tiles = 0;
for (const x of (await readdir(dir)).sort()) {
  for (const f of (await readdir(path.join(dir, x))).sort()) {
    if (tiles >= TILES) break;
    tiles++;
    const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
    const layer = (name) => {
      const l = tile.layers[name];
      return Array.from({ length: l ? l.length : 0 }, (_, i) => feature(l.feature(i).toGeoJSON(Number(x), parseInt(f), 14).geometry));
    };
    const [roads, buildings, contours, waters, labels] = ["road", "building", "contour", "waterarea", "label"].map(layer);
    for (const tolerance of [1e-5, 1e-4, 1e-3]) {
      for (const highQuality of [false, true]) {
        for (const [name, fs] of [["roads", roads.slice(0, 500)], ["buildings", buildings.slice(0, 500)], ["contours", contours], ["water", waters]]) {
          // Positions parsed from JSON, as the table holds them: Turf compares the closing point by identity.
          const want = fs.map((g) => attempt(() => simplify(JSON.parse(JSON.stringify(g)), { tolerance, highQuality }).geometry.coordinates));
          const got = attempt(() => op(fs, "simplify", tolerance, highQuality ? 1 : 0).map((g) => g.geometry?.coordinates ?? null));
          check(`gsi simplify ${name}`, `${x}/${f} ${tolerance} ${highQuality}`, want, got);
        }
      }
    }
    hulls("gsi buildings", buildings.slice(0, 2000));
    hulls("gsi water", waters);
    if (labels.length >= 3) delaunay("gsi labels", labels);
    const lines = [...roads.slice(0, 300), ...contours];
    for (let k = 0; k < 10; k++) {
      // A point near a line of the tile.
      const [lx, ly] = lines[(k * 37) % lines.length].geometry.coordinates.flat(2).slice(0, 2);
      const [px, py] = [lx + (rand() - 0.5) * 0.01, ly + (rand() - 0.5) * 0.01];
      const got = attempt(() => nearest(lines, px, py));
      const want = lines.map((l) => {
        const n = nearestPointOnLine(l, [px, py]);
        return [...n.geometry.coordinates, n.properties.dist, n.properties.location, n.properties.index, n.properties.multiFeatureIndex];
      });
      check("gsi nearestPointOnLine", `${x}/${f} ${px},${py}`, want, typeof got === "string" ? got : want.map((_, i) => Array.from(got.subarray(i * 6, i * 6 + 6))));
      const [sx, sy, ex, ey] = [...lines[k % lines.length].geometry.coordinates[0], px, py];
      const singles = lines.filter((l) => l.geometry.type === "LineString");
      const sliced = attempt(() => op(singles, "line_slice", sx, sy, ex, ey).map((g) => g.geometry?.coordinates ?? null));
      check("gsi lineSlice", `${x}/${f} ${k}`, singles.map((l) => attempt(() => lineSlice([sx, sy], [ex, ey], l).geometry.coordinates)), sliced);
    }
  }
}

console.table(results);
for (const f of failures.slice(0, 10)) console.log(JSON.stringify(f).slice(0, 900));
const ok = failures.length === 0;
await writeFile(path.join(ROOT, "bench/results/shapes-golden.json"), JSON.stringify({ tiles: TILES, results, failures, ok }, null, 2) + "\n");
console.log(ok ? "all identical" : `${failures.length} differ`);
process.exit(ok ? 0 : 1);
