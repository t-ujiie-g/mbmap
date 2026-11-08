// shapes.wasm vs Turf 7.4.0, concaveman 2.0.0, d3-delaunay 6.0.6 and delaunator 5.1.0 on shapes:golden's
// kinds of input: GSI roads, buildings and contours, random points. A table result is kept as a dataset, as
// the worker keeps it. Usage: node shapes/node.mjs [--tiles=4]; writes bench/results/shapes-node.json.
import simplify from "@turf/simplify";
import convex from "@turf/convex";
import concaveman from "concaveman";
import Delaunator from "delaunator";
import { Delaunay } from "d3-delaunay";
import { nearestPointOnLine } from "@turf/nearest-point-on-line";
import { lineSlice } from "@turf/line-slice";
import { arg } from "../lib/args.mjs";
import { fc, f64sOf, gsiTiles, loadModules, rng, rows, time, TIMING, writeResults } from "../lib/analysis-modules.mjs";

const TILES = Number(arg("tiles", 4));
const env = await loadModules("shapes");
const { m } = env;
const { all, row } = rows();
const op = (id, name, ...args) => {
  env.put([id]);
  env.store(m[name](...args));
};
const transfer = (ids) => ({ tablesIn: time(() => ids.forEach((id) => env.put([id]))) });

const tiles = await gsiTiles(TILES);
const layers = (name, n = Infinity) => tiles.map((t) => t.layer(name).slice(0, n));
const roads = layers("road");
const buildings = layers("building");
const contours = layers("contour");
const ids = (sets) => sets.map((s) => env.load(fc(s)));
const count = (sets) => sets.reduce((s, fs) => s + fs.length, 0);

for (const [name, sets] of [["roads", roads], ["buildings", buildings], ["contours", contours]]) {
  const d = ids(sets);
  for (const highQuality of [false, true]) {
    row(`simplify ${name} (${count(sets)} features, 1e-4, highQuality ${highQuality})`,
      time(() => sets.forEach((fs) => fs.forEach((f) => simplify(f, { tolerance: 1e-4, highQuality })))),
      time(() => d.forEach((id) => op(id, "simplify", 1e-4, highQuality ? 1 : 0))),
      transfer(d));
  }
  d.forEach(env.dispose);
}

// Hulls of each tile's first 2000 buildings.
const hullSets = layers("building", 2000);
const hullIds = ids(hullSets);
const vertices = hullSets.map((fs) => {
  const out = [];
  const flat = (c) => (typeof c[0] === "number" ? out.push(c) : c.forEach(flat));
  fs.forEach((f) => flat(f.geometry.coordinates));
  return out;
});
row(`convex hull (${count(hullSets)} buildings)`, time(() => hullSets.forEach((fs) => convex(fc(fs)))), time(() => hullIds.forEach((id) => op(id, "convex"))), transfer(hullIds));
row(`concave hull (${vertices.reduce((s, v) => s + v.length, 0)} vertices, concavity 2)`, time(() => vertices.forEach((v) => concaveman(v, 2, 0))), time(() => hullIds.forEach((id) => op(id, "concave", 2, 0))), transfer(hullIds));
hullIds.forEach(env.dispose);

// Delaunay and Voronoi of random points; JS builds the same polygons the table holds.
const rand = rng(192);
const box = [139.69, 35.59, 139.81, 35.71];
for (const n of [1000, 10000, 100000]) {
  const coords = Array.from({ length: n }, () => [139.7 + rand() * 0.1, 35.6 + rand() * 0.1]);
  const id = env.load(fc(coords.map((c) => ({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: c } }))));
  row(`delaunay ${n} points (JS: d3-delaunay and its triangle polygons)`, time(() => Array.from(Delaunay.from(coords).trianglePolygons())), time(() => op(id, "delaunay")), {
    ...transfer([id]),
    exportOnly: time(() => {
      env.put([id]);
      m.delaunay();
    }),
  });
  row(`delaunay ${n} points (JS: delaunator, indices only)`, time(() => new Delaunator(coords.flat())), time(() => op(id, "delaunay")));
  row(`voronoi ${n} points (JS: d3-delaunay's cell polygons)`, time(() => {
    const v = Delaunay.from(coords).voronoi(box);
    for (let i = 0; i < n; i++) v.cellPolygon(i);
  }), time(() => op(id, "voronoi", ...box)));
  env.dispose(id);
}

// Ten points near the lines of each tile, as shapes:golden picks them.
const lineSets = tiles.map((t, k) => [...roads[k].slice(0, 300), ...contours[k]]);
const lineIds = ids(lineSets);
const near = lineSets.map((lines) => Array.from({ length: 10 }, (_, k) => {
  const [lx, ly] = lines[(k * 37) % lines.length].geometry.coordinates.flat(2).slice(0, 2);
  return [lx + (rand() - 0.5) * 0.01, ly + (rand() - 0.5) * 0.01];
}));
row(`nearestPointOnLine (${count(lineSets)} lines x 10 points)`,
  time(() => lineSets.forEach((lines, k) => near[k].forEach((p) => lines.forEach((l) => nearestPointOnLine(l, p))))),
  time(() => lineIds.forEach((id, k) => near[k].forEach(([x, y]) => {
    env.put([id]);
    f64sOf(m, m.nearest_on_line(x, y));
  }))),
  { tablesIn: time(() => lineIds.forEach((id) => near[0].forEach(() => env.put([id])))) });
lineIds.forEach(env.dispose);
const singles = lineSets.map((lines) => lines.filter((l) => l.geometry.type === "LineString"));
const singleIds = ids(singles);
const slices = singles.map((lines, k) => near[k].map((p, j) => [...lines[j % lines.length].geometry.coordinates[0], ...p]));
row(`lineSlice (${count(singles)} lines x 10 cuts)`,
  time(() => singles.forEach((lines, k) => slices[k].forEach(([sx, sy, ex, ey]) => lines.forEach((l) => lineSlice([sx, sy], [ex, ey], l))))),
  time(() => singleIds.forEach((id, k) => slices[k].forEach((s) => op(id, "line_slice", ...s)))),
  { tablesIn: time(() => singleIds.forEach((id) => slices[0].forEach(() => env.put([id])))) });
singleIds.forEach(env.dispose);

await writeResults("shapes-node", { tiles: TILES, statistic: TIMING, columns: "mbmap: the dataset's table out of analysis.wasm and into shapes.wasm, the export, a table result read back into analysis.wasm as a dataset; tablesIn: the copies in alone; exportOnly: the copies in and the export, its table left in shapes.wasm" }, all);
