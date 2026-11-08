// route.wasm vs geojson-path-finder 2.1.0 on route:golden's networks: GSI roads per tile and a jittered grid.
// Building includes the dataset's table copied into route.wasm; queries are between random vertices.
// Usage: node route/node.mjs [--tiles=4] [--queries=200]; writes bench/results/route-node.json.
import pathFinder from "geojson-path-finder";
import { arg } from "../lib/args.mjs";
import { fc, f64sOf, gsiTiles, loadModules, rng, rows, time, TIMING, writeResults } from "../lib/analysis-modules.mjs";

const PathFinder = pathFinder.default ?? pathFinder;
const TILES = Number(arg("tiles", 4));
const QUERIES = Number(arg("queries", 200));
const env = await loadModules("route");
const { m } = env;
const { all, row } = rows();
const rand = rng(196);
const line = (coordinates) => ({ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates } });
const pointOf = (c) => ({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: c } });

const networks = [];
for (const t of await gsiTiles(TILES)) {
  const features = [];
  for (const f of t.layer("road")) {
    if (f.geometry.type === "LineString") features.push(line(f.geometry.coordinates));
    else if (f.geometry.type === "MultiLineString") for (const c of f.geometry.coordinates) features.push(line(c));
  }
  networks.push(["gsi roads", fc(features), 1e-5]);
}
const [n, cell] = [100, 0.001];
const at = Array.from({ length: n }, (_, i) => Array.from({ length: n }, (_, j) => [139.7 + j * cell + (rand() - 0.5) * cell * 0.2, 35.6 + i * cell + (rand() - 0.5) * cell * 0.2]));
const grid = [["grid 100 x 100", fc([...at.map((r) => line(r)), ...at[0].map((_, j) => line(at.map((r) => r[j])))]), 1e-5]];

for (const [name, sets] of [[`gsi roads (${TILES} tiles)`, networks], ["jittered grid 100 x 100", grid]]) {
  const ids = sets.map(([, data]) => env.load(data));
  const lines = sets.reduce((s, [, data]) => s + data.features.length, 0);
  const build = (k) => {
    env.put([ids[k]]);
    return m.network_new(sets[k][2], 0);
  };
  row(`${name}: build the network (${lines} lines)`,
    time(() => sets.forEach(([, data, tolerance]) => new PathFinder(data, { tolerance }))),
    time(() => sets.forEach((_, k) => m.network_dispose(build(k)))),
    { tablesIn: time(() => ids.forEach((id) => env.put([id]))) });
  const finders = sets.map(([, data, tolerance]) => new PathFinder(data, { tolerance }));
  const handles = sets.map((_, k) => build(k));
  const queries = sets.map(([, data]) => {
    const vertices = data.features.flatMap((f) => f.geometry.coordinates);
    return Array.from({ length: QUERIES }, () => [vertices[Math.floor(rand() * vertices.length)], vertices[Math.floor(rand() * vertices.length)]]);
  });
  const found = queries.reduce((s, qs, k) => s + qs.filter(([p, q]) => finders[k].findPath(pointOf(p), pointOf(q))).length, 0);
  row(`${name}: ${QUERIES * sets.length} paths between vertices (${found} found)`,
    time(() => queries.forEach((qs, k) => qs.forEach(([p, q]) => finders[k].findPath(pointOf(p), pointOf(q))))),
    time(() => queries.forEach((qs, k) => qs.forEach(([p, q]) => f64sOf(m, m.network_path(handles[k], ...p, ...q))))));
  handles.forEach((h) => m.network_dispose(h));
  ids.forEach(env.dispose);
}

await writeResults("route-node", { pathFinder: "2.1.0", tiles: TILES, queries: QUERIES, statistic: TIMING, columns: "mbmap build: the dataset's table into route.wasm and network_new; paths: network_path and its f64s read; tablesIn: the copies in alone" }, all);
