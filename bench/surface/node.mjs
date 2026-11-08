// surface.wasm vs Turf 7.4.0 and d3-contour 4.0.3 on surface:golden's kinds of input, larger: grids over a
// box, IDW of random points, isolines and isobands of a point grid, density, DBSCAN and k-means of GSI buildings'
// first vertices. Usage: node surface/node.mjs [--tiles=4]; writes bench/results/surface-node.json.
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
import { arg } from "../lib/args.mjs";
import { fc, f64sOf, gsiTiles, loadModules, rng, rows, time, TIMING, writeResults } from "../lib/analysis-modules.mjs";

const TILES = Number(arg("tiles", 4));
const env = await loadModules("surface");
const { m } = env;
const { all, row } = rows();
const encoder = new TextEncoder();
// A surface_worker export as the worker calls it: table, text, f64s; a table result kept as a dataset.
function call(fn, id, args, text = "", numbers = []) {
  const name = encoder.encode(text);
  const len = env.put(id === -1 ? [] : [id], [name, new Uint8Array(Float64Array.from(numbers).buffer)]);
  return m[fn](len, name.length, ...args);
}
const table = (...a) => env.store(call(...a));
const values = (...a) => f64sOf(m, call(...a));
const transfer = (id) => ({ tablesIn: time(() => env.put([id])) });
const point = (c, properties = {}) => ({ type: "Feature", properties, geometry: { type: "Point", coordinates: c } });

const box = [139.7, 35.6, 139.8, 35.7];
for (const [fn, turf, cell] of [["point_grid", pointGrid, 0.1], ["square_grid", squareGrid, 0.1], ["hex_grid", hexGrid, 0.1], ["triangle_grid", triangleGrid, 0.1]]) {
  const n = turf(box, cell).features.length;
  row(`${fn} ${cell} km over 0.1° (${n} cells)`, time(() => turf(box, cell)), time(() => table(fn, -1, [...box, cell, 0])),
    { exportOnly: time(() => call(fn, -1, [...box, cell, 0])) });
}

const rand = rng(194);
const scattered = Array.from({ length: 200 }, () => point([139.7 + rand() * 0.1, 35.6 + rand() * 0.1], { elevation: Math.round(rand() * 1000) / 10 }));
const scatteredId = env.load(fc(scattered));
for (const [gridType, code] of [["point", 0], ["square", 1], ["hex", 2]]) {
  row(`interpolate (IDW) 200 points, 0.25 km ${gridType} grid`,
    time(() => interpolate(fc(scattered), 0.25, { gridType, property: "elevation", weight: 2 })),
    time(() => table("interpolate", scatteredId, [0.25, code, 2], "elevation")), transfer(scatteredId));
}
env.dispose(scatteredId);

const grid = pointGrid([139.6, 35.5, 139.8, 35.7], 0.25).features.map((f) => {
  const [x, y] = f.geometry.coordinates;
  return point(f.geometry.coordinates, { elevation: Math.round(100 * Math.sin((x - 139.6) * 40) * Math.cos((y - 35.5) * 30) + 100) });
});
const gridId = env.load(fc(grid));
const breaks = [0, 25, 50, 75, 100, 150, 200];
row(`isolines (${grid.length}-point grid, 7 breaks)`, time(() => isolines(fc(grid), breaks, { zProperty: "elevation" })), time(() => table("isolines", gridId, [], "elevation", breaks)),
  { ...transfer(gridId), exportOnly: time(() => call("isolines", gridId, [], "elevation", breaks)) });
row(`isobands (${grid.length}-point grid, 7 breaks)`, time(() => isobands(fc(grid), breaks, { zProperty: "elevation" })), time(() => table("isobands", gridId, [], "elevation", breaks)), transfer(gridId));
env.dispose(gridId);

// d3's density in degrees, on surface:golden's pixel grid over the points' box.
function density(points) {
  const xs = points.map((p) => p.geometry.coordinates[0]);
  const ys = points.map((p) => p.geometry.coordinates[1]);
  const [x0, y0, x1, y1] = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
  const [sx, sy] = [x1 - x0, y1 - y0];
  const d = contourDensity().x((p) => (p.geometry.coordinates[0] - x0) / sx * 960).y((p) => (y1 - p.geometry.coordinates[1]) / sy * 500).size([960, 500]);
  return d(points).map((c) => c.coordinates.map((poly) => poly.map((ring) => ring.map(([px, py]) => [x0 + px / 960 * sx, y1 - py / 500 * sy]))));
}
const tiles = await gsiTiles(TILES);
const gsi = tiles.flatMap((t) => t.layer("building").slice(0, 1500).map((f) => point(f.geometry.coordinates.flat(3).slice(0, 2))));
const gsiId = env.load(fc(gsi));
row(`density (${gsi.length} GSI points, 960 x 500, 20 thresholds)`, time(() => density(gsi)), time(() => table("density", gsiId, [NaN, NaN, NaN, NaN, 960, 500, 4, 20.4939015319192, 20, 0])), transfer(gsiId));
for (const [maxDistance, minPoints] of [[0.3, 3], [2, 3]]) {
  row(`dbscan (${gsi.length} GSI points, ${maxDistance} km, ${minPoints})`, time(() => clustersDbscan(fc(gsi), maxDistance, { minPoints })), time(() => values("dbscan", gsiId, [maxDistance, minPoints])), transfer(gsiId));
}
for (const k of [0, 20]) {
  row(`kmeans (${gsi.length} GSI points, k ${k || "default"})`, time(() => clustersKmeans(fc(gsi), k ? { numberOfClusters: k } : {})), time(() => values("kmeans", gsiId, [k])), transfer(gsiId));
}
env.dispose(gsiId);

await writeResults("surface-node", { tiles: TILES, statistic: TIMING, columns: "mbmap: the dataset's table (with the property name and numbers) into surface.wasm, the export, a table result read back into analysis.wasm as a dataset (f64s for dbscan and kmeans); tablesIn: the copies in alone; exportOnly: the copies in and the export, its table left in surface.wasm" }, all);
