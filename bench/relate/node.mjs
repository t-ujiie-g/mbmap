// relate.wasm vs JSTS 2.12.1 on relate:golden's inputs: predicates over GSI tile pairs and random sets, DE-9IM
// matrices of random pairs. JSTS finds candidates with flatbush over the envelopes, as relate_worker uses its index.
// Usage: node relate/node.mjs [--tiles=4]; writes bench/results/relate-node.json.
import Flatbush from "flatbush";
import GeoJSONReader from "jsts/org/locationtech/jts/io/GeoJSONReader.js";
import RelateOp from "jsts/org/locationtech/jts/operation/relate/RelateOp.js";
import "jsts/org/locationtech/jts/monkey.js";
import { arg } from "../lib/args.mjs";
import { fc, gsiTiles, loadModules, outputOf, rng, rows, time, TIMING, writeResults } from "../lib/analysis-modules.mjs";

const TILES = Number(arg("tiles", 4));
const RELATIONS = ["intersects", "contains", "within", "covers", "coveredBy", "touches", "crosses", "overlaps", "equals"];
const env = await loadModules("relate");
const { m } = env;
const reader = new GeoJSONReader();
const { all, row } = rows();

// Pairs of `left` x `right` in `relation`, JSTS on the pairs whose envelopes meet.
function jsPairs(left, right, relation) {
  const ix = new Flatbush(right.length);
  for (const g of right) {
    const e = g.getEnvelopeInternal();
    ix.add(e.getMinX(), e.getMinY(), e.getMaxX(), e.getMaxY());
  }
  ix.finish();
  const out = [];
  for (let i = 0; i < left.length; i++) {
    const e = left[i].getEnvelopeInternal();
    for (const j of ix.search(e.getMinX(), e.getMinY(), e.getMaxX(), e.getMaxY())) if (left[i][relation === "equals" ? "equalsTopo" : relation](right[j])) out.push(i, j);
  }
  return out;
}
const mbmapPairs = (a, b, code) => {
  const lenA = env.put([a, b]);
  return new Int32Array(outputOf(m, m.relate_pairs(lenA, code, 0) * 4).buffer);
};

// Sets: [name, left geometries, right geometries] summed over the tiles.
const tiles = await gsiTiles(TILES);
const sets = { "gsi buildings x roads": [], "gsi water x roads": [], "gsi roads x roads (200)": [], "gsi buildings x buildings (200)": [] };
for (const t of tiles) {
  const areas = (fs) => fs.filter((f) => /Polygon/.test(f.geometry.type));
  const lines = (fs) => fs.filter((f) => /LineString/.test(f.geometry.type));
  const [buildings, water, roads] = [areas(t.layer("building")), areas(t.layer("waterarea")), lines(t.layer("road"))];
  sets["gsi buildings x roads"].push([buildings, roads]);
  sets["gsi water x roads"].push([water, roads]);
  sets["gsi roads x roads (200)"].push([roads.slice(0, 200), roads.slice(0, 200)]);
  sets["gsi buildings x buildings (200)"].push([buildings.slice(0, 200), buildings.slice(0, 200)]);
}

// Random grid shapes as relate:golden makes them.
const rand = rng(19);
const int = (n) => Math.floor(rand() * n);
const pt = () => [int(9), int(9)];
const ring = (pts) => [...pts, pts[0]];
const box = (x0, y0, x1, y1) => ring([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]);
const feature = (geometry) => ({ type: "Feature", properties: {}, geometry });
const SHAPES = [
  () => ({ type: "Point", coordinates: pt() }),
  () => ({ type: "MultiPoint", coordinates: [pt(), pt(), pt()] }),
  () => ({ type: "LineString", coordinates: Array.from({ length: 2 + int(3) }, pt) }),
  () => ({ type: "MultiLineString", coordinates: [[pt(), pt()], [pt(), pt(), pt()]] }),
  () => {
    const [x, y] = pt();
    return { type: "Polygon", coordinates: [box(x, y, x + 1 + int(4), y + 1 + int(4))] };
  },
  () => {
    const [x, y] = pt();
    const s = 3 + int(3);
    return { type: "Polygon", coordinates: [box(x, y, x + s, y + s), box(x + 1, y + 1, x + s - 1, y + s - 1).reverse()] };
  },
];
const random = (n) => Array.from({ length: n }, () => feature(SHAPES[int(SHAPES.length)]()));
sets["random sets (20 of 60 x 60)"] = Array.from({ length: 20 }, () => [random(60), random(60)]);

const allFeatures = tiles.flatMap((t) => [...t.layer("building"), ...t.layer("waterarea"), ...t.layer("road")]);
row(`read GeoJSON (${allFeatures.length} GSI features; mbmap: JSON text into a dataset)`,
  time(() => allFeatures.map((f) => reader.read(f.geometry))),
  time(() => env.dispose(env.load(fc(allFeatures)))),
  { stringify: time(() => JSON.stringify(fc(allFeatures))) });

for (const [name, pairs] of Object.entries(sets)) {
  const js = pairs.map(([l, r]) => [l.map((f) => reader.read(f.geometry)), r.map((f) => reader.read(f.geometry))]);
  const ids = pairs.map(([l, r]) => [env.load(fc(l)), env.load(fc(r))]);
  for (const relation of ["intersects", "touches"]) {
    const code = RELATIONS.indexOf(relation);
    const want = js.reduce((s, [l, r]) => s + jsPairs(l, r, relation).length, 0);
    const got = ids.reduce((s, [a, b]) => s + mbmapPairs(a, b, code).length, 0);
    if (want !== got) throw new Error(`${name} ${relation}: ${got} vs ${want}`);
    row(`${name} ${relation} (${want / 2} pairs)`,
      time(() => js.forEach(([l, r]) => jsPairs(l, r, relation))),
      time(() => ids.forEach(([a, b]) => mbmapPairs(a, b, code))),
      { tablesIn: time(() => ids.forEach(([a, b]) => env.put([a, b]))) });
  }
  for (const [a, b] of ids) env.dispose(a), env.dispose(b);
}

// Matrices of pairs (left[k], right[k]) of 100-row datasets, one call a pair: the worker copies both tables each time.
const [left, right] = [random(100), random(100)];
const [jl, jr] = [left.map((f) => reader.read(f.geometry)), right.map((f) => reader.read(f.geometry))];
const [la, rb] = [env.load(fc(left)), env.load(fc(right))];
const decoder = new TextDecoder();
const matrix = (k) => decoder.decode(outputOf(m, m.relate_matrix(env.put([la, rb]), k, k)));
for (let k = 0; k < 100; k++) if (matrix(k) !== RelateOp.relate(jl[k], jr[k]).toString()) throw new Error(`matrix ${k} differs`);
row("100 DE-9IM matrices (random pairs, tables copied per call)",
  time(() => { for (let k = 0; k < 100; k++) RelateOp.relate(jl[k], jr[k]).toString(); }),
  time(() => { for (let k = 0; k < 100; k++) matrix(k); }),
  { tablesIn: time(() => { for (let k = 0; k < 100; k++) env.put([la, rb]); }) });

await writeResults("relate-node", { jsts: "2.12.1", tiles: TILES, statistic: TIMING, columns: "mbmap: both datasets' tables out of analysis.wasm and into relate.wasm, the export, the result read; tablesIn: those copies alone" }, all);
