// surface.wasm vs Turf 7.4.0 (point / square / hex / triangle grids, interpolate, isolines, isobands,
// clustersDbscan, clustersKmeans) and d3-contour 4.0.3 (contourDensity) on random points and GSI
// features; every coordinate, value and cluster must be identical (Object.is).
// Usage: node surface/golden.mjs [--tiles=N]; writes bench/results/surface-golden.json.
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { pointGrid } from "@turf/point-grid";
import { squareGrid } from "@turf/square-grid";
import { hexGrid } from "@turf/hex-grid";
import { triangleGrid } from "@turf/triangle-grid";
import { interpolate } from "@turf/interpolate";
import { isolines } from "@turf/isolines";
import { isobands } from "@turf/isobands";
import { clustersDbscan } from "@turf/clusters-dbscan";
import { clustersKmeans } from "@turf/clusters-kmeans";
import { contourDensity } from "d3-contour";
import { hostNumber, hostText } from "../../wasmio/js/host.mjs";
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
const { instance: si } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/surface_worker/surface_worker.wasm")), { Math, host: hostText() });
const s = si.exports;
const decoder = new TextDecoder();
const encoder = new TextEncoder();
const put = (e, bytes) => {
  const at = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
};
const out = (e, n) => {
  if (n < 0) throw new Error(decoder.decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
};
function table(features) {
  if (!features) return new Uint8Array(0);
  put(a, encoder.encode(JSON.stringify({ type: "FeatureCollection", features })));
  const id = a.load();
  if (id < 0) throw new Error("load failed");
  const bytes = out(a, a.table_out(id));
  a.dispose(id);
  return bytes;
}
// A surface_worker export as analysis_worker/js/worker.mjs calls it: table, text, f64s.
function call(fn, features, args, text = "", numbers = []) {
  const t = table(features);
  const name = encoder.encode(text);
  const all = new Uint8Array(t.length + name.length + numbers.length * 8);
  all.set(t);
  all.set(name, t.length);
  all.set(new Uint8Array(Float64Array.from(numbers).buffer), t.length + name.length);
  put(s, all);
  return s[fn](t.length, name.length, ...args);
}
const tableOf = (fn, features, args, text, numbers) => tableToGeoJSON(out(s, call(fn, features, args, text, numbers))).features;
const valuesOf = (fn, features, args) => new Float64Array(out(s, call(fn, features, args) * 8).buffer);

const results = {};
const failures = [];
const same = (x, y) =>
  Array.isArray(x) ? Array.isArray(y) && x.length === y.length && x.every((v, i) => same(v, y[i]))
  : x && typeof x === "object" ? y && typeof y === "object" && Object.keys(x).length === Object.keys(y).length && Object.keys(x).every((k) => same(x[k], y[k]))
  : Object.is(x, y);
// Where two values first differ, as a path.
function firstDiff(x, y, at = "") {
  if (same(x, y)) return null;
  if (Array.isArray(x) && Array.isArray(y)) {
    if (x.length !== y.length) return `${at} length ${x.length} vs ${y.length}`;
    for (let i = 0; i < x.length; i++) if (!same(x[i], y[i])) return firstDiff(x[i], y[i], `${at}[${i}]`);
  }
  return `${at}: ${JSON.stringify(x)?.slice(0, 120)} vs ${JSON.stringify(y)?.slice(0, 120)}`;
}
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, identical: 0 });
  r.cases++;
  if (same(want, got)) r.identical++;
  else if (failures.length < 30) failures.push({ group, label, want: JSON.stringify(want)?.slice(0, 400), got: JSON.stringify(got)?.slice(0, 400), first: firstDiff(want, got) });
}
const attempt = (f) => {
  try {
    return f();
  } catch (err) {
    return `error: ${err.message}`;
  }
};
// Features as [coordinates, properties]; empty coordinates as null, as a Table holds a line or band meeting no cell.
const coordinates = (g) => (g?.coordinates?.length ? g.coordinates : null);
const shape = (fs) => (Array.isArray(fs) ? fs.map((f) => [coordinates(f.geometry), f.properties ?? {}]) : fs);

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(194);
const point = (c, properties = {}) => ({ type: "Feature", properties, geometry: { type: "Point", coordinates: c } });

// Grids.
const GRIDS = [["point_grid", pointGrid], ["square_grid", squareGrid], ["hex_grid", hexGrid], ["triangle_grid", triangleGrid]];
const boxes = [[139.7, 35.6, 139.8, 35.7], [-0.4, -0.3, 0.5, 0.4], [10, 70, 16, 76], [135.2, 34.6, 135.6, 34.8]];
for (const box of boxes) {
  for (const cell of [1, 2.5, 7]) {
    for (const [fn, turf] of GRIDS) {
      if ((box[2] - box[0]) * 111 / cell > 300) continue;
      check(`grid ${fn}`, `${box} ${cell}`, shape(turf(box, cell).features), attempt(() => shape(tableOf(fn, null, [...box, cell, 0]))));
    }
    check("grid hex triangles", `${box} ${cell}`, shape(hexGrid(box, cell, { triangles: true }).features), attempt(() => shape(tableOf("hex_grid", null, [...box, cell, 1]))));
  }
}

// Interpolation of random points.
for (let k = 0; k < 12; k++) {
  const points = Array.from({ length: 5 + Math.floor(rand() * 40) }, () => point([139.7 + rand() * 0.1, 35.6 + rand() * 0.1], { elevation: Math.round(rand() * 1000) / 10 }));
  const cell = [0.5, 1, 2][k % 3];
  for (const [gridType, code] of [["point", 0], ["square", 1], ["hex", 2], ["triangle", 3]]) {
    for (const weight of [1, 2, 0.5]) {
      const want = attempt(() => shape(interpolate({ type: "FeatureCollection", features: points }, cell, { gridType, property: "elevation", weight }).features));
      check(`interpolate ${gridType}`, `${k} ${weight}`, want, attempt(() => shape(tableOf("interpolate", points, [cell, code, weight], "elevation"))));
    }
  }
}

// Isolines and isobands of point grids with smooth and random values.
for (let k = 0; k < 10; k++) {
  const grid = pointGrid([139.6 + k * 0.01, 35.5, 139.8, 35.7], 1 + (k % 3)).features.map((f) => {
    const [x, y] = f.geometry.coordinates;
    const z = k % 2 ? Math.round(rand() * 100) : Math.round(100 * Math.sin((x - 139.6) * 40) * Math.cos((y - 35.5) * 30) + 100);
    return point(f.geometry.coordinates, { elevation: z });
  });
  const breaks = k % 3 ? [20, 50, 80, 120, 160] : [0, 25, 50, 75, 100, 150, 200];
  const fc = { type: "FeatureCollection", features: grid };
  check("isolines", k, attempt(() => shape(isolines(fc, breaks, { zProperty: "elevation" }).features)), attempt(() => shape(tableOf("isolines", grid, [], "elevation", breaks))));
  check("isobands", k, attempt(() => shape(isobands(fc, breaks, { zProperty: "elevation" }).features)), attempt(() => shape(tableOf("isobands", grid, [], "elevation", breaks))));
}

// d3's density of points in degrees, on a pixel grid over their box, taken back as the worker does.
function density(points, { width = 960, height = 500, cellSize = 4, bandwidth = 20.4939015319192, thresholds = 20, weight }) {
  const xs = points.map((p) => p.geometry.coordinates[0]);
  const ys = points.map((p) => p.geometry.coordinates[1]);
  const [x0, y0, x1, y1] = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
  const [sx, sy] = [x1 - x0, y1 - y0];
  const d = contourDensity()
    .x((p) => (p.geometry.coordinates[0] - x0) / sx * width)
    .y((p) => (y1 - p.geometry.coordinates[1]) / sy * height)
    .size([width, height]).cellSize(cellSize).bandwidth(bandwidth).thresholds(thresholds);
  if (weight) d.weight((p) => p.properties[weight]);
  return d(points).map((c) => [c.coordinates.map((poly) => poly.map((ring) => ring.map(([px, py]) => [x0 + px / width * sx, y1 - py / height * sy]))), { value: c.value }]);
}
for (let k = 0; k < 12; k++) {
  const centers = Array.from({ length: 1 + (k % 4) }, () => [139.7 + rand() * 0.1, 35.6 + rand() * 0.1]);
  const points = Array.from({ length: 50 + Math.floor(rand() * 400) }, () => {
    const c = centers[Math.floor(rand() * centers.length)];
    return point([c[0] + (rand() - 0.5) * 0.02, c[1] + (rand() - 0.5) * 0.02], { w: Math.round(rand() * 10) });
  });
  const options = [{}, { width: 400, height: 300, cellSize: 2, bandwidth: 10 }, { cellSize: 8, thresholds: 8, weight: "w" }][k % 3];
  const { width = 960, height = 500, cellSize = 4, bandwidth = 20.4939015319192, thresholds = 20, weight } = options;
  check("density", k, density(points, options), attempt(() => shape(tableOf("density", points, [NaN, NaN, NaN, NaN, width, height, cellSize, bandwidth, thresholds, weight ? 1 : 0], weight ?? ""))));
}

// DBSCAN and k-means.
function clusters(group, points) {
  const fc = () => ({ type: "FeatureCollection", features: JSON.parse(JSON.stringify(points)) });
  for (const [maxDistance, minPoints] of [[0.3, 3], [0.8, 4], [2, 3]]) {
    const want = clustersDbscan(fc(), maxDistance, { minPoints }).features.flatMap((f) => [f.properties.cluster ?? -1, ["core", "edge", "noise"].indexOf(f.properties.dbscan)]);
    check(`${group} dbscan`, `${points.length} ${maxDistance}`, want, attempt(() => Array.from(valuesOf("dbscan", points, [maxDistance, minPoints]))));
  }
  for (const k of [undefined, 3, 7]) {
    if (k > points.length) continue;
    const r = clustersKmeans(fc(), k === undefined ? {} : { numberOfClusters: k });
    const got = attempt(() => valuesOf("kmeans", points, [k ?? 0]));
    const clustersGot = typeof got === "string" ? got : Array.from(got.subarray(1, 1 + got[0]));
    check(`${group} kmeans`, `${points.length} ${k}`, r.features.map((f) => f.properties.cluster), clustersGot);
    if (typeof got !== "string") {
      const centroids = new Map(r.features.map((f) => [f.properties.cluster, f.properties.centroid]));
      check(`${group} kmeans centroids`, `${points.length} ${k}`, [...centroids].sort((p, q) => p[0] - q[0]).map(([c, xy]) => xy), [...centroids.keys()].sort((p, q) => p - q).map((c) => [got[1 + got[0] + c * 2], got[2 + got[0] + c * 2]]));
    }
  }
}
for (let k = 0; k < 10; k++) {
  const centers = Array.from({ length: 2 + (k % 3) }, () => [139.7 + rand() * 0.1, 35.6 + rand() * 0.1]);
  clusters("random", Array.from({ length: 30 + Math.floor(rand() * 300) }, () => {
    const c = centers[Math.floor(rand() * centers.length)];
    return point([c[0] + (rand() - 0.5) * 0.02, c[1] + (rand() - 0.5) * 0.02]);
  }));
}

// GSI: the first vertex of each building as points.
const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
let tiles = 0;
for (const x of (await readdir(dir)).sort()) {
  for (const f of (await readdir(path.join(dir, x))).sort()) {
    if (tiles++ >= TILES) break;
    const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
    const l = tile.layers.building;
    const points = [];
    for (let i = 0; l && i < l.length && points.length < 1500; i++) points.push(point(l.feature(i).toGeoJSON(Number(x), parseInt(f), 14).geometry.coordinates.flat(3).slice(0, 2)));
    clusters("gsi", points);
    check("gsi density", `${x}/${f}`, density(points, {}), attempt(() => shape(tableOf("density", points, [NaN, NaN, NaN, NaN, 960, 500, 4, 20.4939015319192, 20, 0]))));
  }
}

console.table(results);
for (const f of failures.slice(0, 10)) console.log(JSON.stringify(f).slice(0, 900));
const ok = failures.length === 0;
await writeFile(path.join(ROOT, "bench/results/surface-golden.json"), JSON.stringify({ tiles: TILES, results, failures, ok }, null, 2) + "\n");
console.log(ok ? "all identical" : `${failures.length} differ`);
process.exit(ok ? 0 : 1);
