// relate.wasm (DE-9IM) vs JSTS 2.12.1's RelateOp and predicates on hand-written, random grid and GSI
// features; every matrix and every predicate's pairs must be identical.
// Usage: node relate/golden.mjs [--cases=N] [--tiles=N]; writes bench/results/relate-golden.json.
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import GeoJSONReader from "jsts/org/locationtech/jts/io/GeoJSONReader.js";
import RelateOp from "jsts/org/locationtech/jts/operation/relate/RelateOp.js";
import "jsts/org/locationtech/jts/monkey.js";
import { hostNumber } from "../../wasmio/js/host.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const CASES = Number(arg("cases", 20000));
const TILES = Number(arg("tiles", 4));
const RELATIONS = ["intersects", "contains", "within", "covers", "coveredBy", "touches", "crosses", "overlaps", "equals"];
const JSTS_METHOD = { equals: "equalsTopo" };

let a;
const { instance: ai } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm")),
  { Math, host: { number: hostNumber(() => a.memory) } },
);
a = ai.exports;
const { instance: ri } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/relate_worker/relate_worker.wasm")), {});
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
const load = (geometries) => {
  put(a, new TextEncoder().encode(JSON.stringify({ type: "FeatureCollection", features: geometries.map((geometry) => ({ type: "Feature", properties: {}, geometry })) })));
  const id = a.load();
  if (id < 0) throw new Error("load failed");
  const bytes = out(a, a.table_out(id));
  a.dispose(id);
  return bytes;
};
// Both tables in relate_worker's input, as analysis_worker/js/worker.mjs puts them.
function both(ta, tb) {
  const all = new Uint8Array(ta.length + tb.length);
  all.set(ta);
  all.set(tb, ta.length);
  put(r, all);
  return ta.length;
}
const matrix = (ta, tb, i, j) => decoder.decode(out(r, r.relate_matrix(both(ta, tb), i, j)));
function pairs(ta, tb, code) {
  const n = r.relate_pairs(both(ta, tb), code, 0);
  return new Int32Array(out(r, n * 4).buffer);
}

const reader = new GeoJSONReader();
const results = {};
const failures = [];
function check(group, label, want, got, pairs = 0) {
  const s = (results[group] ??= { cases: 0, identical: 0, pairs: 0 });
  s.cases++;
  s.pairs += pairs;
  if (want === got) s.identical++;
  else if (failures.length < 30) failures.push({ group, label, want, got });
}

// Matrices of pairs (left[k], right[k]), 100 pairs a call.
function matrices(group, left, right) {
  for (let k0 = 0; k0 < left.length; k0 += 100) {
    const ls = left.slice(k0, k0 + 100);
    const rs = right.slice(k0, k0 + 100);
    const [ta, tb] = [load(ls), load(rs)];
    for (let k = 0; k < ls.length; k++) {
      const want = RelateOp.relate(reader.read(ls[k]), reader.read(rs[k])).toString();
      let got;
      try {
        got = matrix(ta, tb, k, k);
      } catch (err) {
        got = `error: ${err.message}`;
      }
      check(group, JSON.stringify([ls[k], rs[k]]), want, got);
    }
  }
}

// Every predicate's pairs over two sets, against JSTS on the pairs whose boxes meet.
function predicates(group, left, right, label = "") {
  const [ta, tb] = [load(left), load(right)];
  const [gl, gr] = [left.map((g) => reader.read(g)), right.map((g) => reader.read(g))];
  const meet = [];
  for (let i = 0; i < gl.length; i++) {
    const ei = gl[i].getEnvelopeInternal();
    for (let j = 0; j < gr.length; j++) if (ei.intersects(gr[j].getEnvelopeInternal())) meet.push([i, j]);
  }
  RELATIONS.forEach((name, code) => {
    const want = meet.filter(([i, j]) => gl[i][JSTS_METHOD[name] ?? name](gr[j])).flat().join(",");
    let got;
    try {
      got = Array.from(pairs(ta, tb, code)).join(",");
    } catch (err) {
      got = `error: ${err.message}`;
    }
    check(`${group} ${name}`, `${label}: ${left.length} x ${right.length}`, want, got, want ? want.split(",").length / 2 : 0);
  });
}

const ring = (pts) => [...pts, pts[0]];
const box = (x0, y0, x1, y1) => ring([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]);
const P = (x, y) => ({ type: "Point", coordinates: [x, y] });
const L = (...c) => ({ type: "LineString", coordinates: c });
const A = (...rings) => ({ type: "Polygon", coordinates: rings });
const square = A(box(0, 0, 4, 4));
const holed = A(box(0, 0, 4, 4), box(1, 1, 3, 3).reverse());
const hand = [
  [P(1, 1), P(1, 1)], [P(1, 1), P(2, 2)], [{ type: "MultiPoint", coordinates: [[0, 0], [1, 1]] }, P(1, 1)],
  [P(2, 2), L([0, 0], [4, 4])], [P(0, 0), L([0, 0], [4, 4])], [P(0, 0), L([0, 0], [4, 0], [4, 4], [0, 0])],
  [P(2, 2), square], [P(0, 2), square], [P(0, 0), square], [P(2, 2), holed], [P(1, 2), holed], [P(9, 9), square],
  [L([0, 0], [4, 4]), L([0, 4], [4, 0])], [L([0, 0], [2, 2]), L([2, 2], [4, 0])], [L([0, 0], [4, 0]), L([1, 0], [3, 0])],
  [L([0, 0], [4, 0]), L([0, 0], [4, 0])], [L([0, 0], [4, 0]), L([4, 0], [0, 0])], [L([0, 0], [2, 0], [4, 0]), L([0, 0], [4, 0])],
  [L([0, 0], [4, 0], [4, 4], [0, 0]), L([4, 4], [8, 8])], [L([0, 0], [1, 0]), L([5, 5], [6, 6])],
  [L([1, 1], [3, 3]), square], [L([2, 2], [6, 2]), square], [L([0, 0], [4, 0]), square], [L([-1, 0], [5, 0]), square],
  [L([4, 4], [6, 6]), square], [L([0, 2], [2, 2]), holed], [L([1, 1], [3, 1]), holed],
  [square, square], [square, A(box(4, 0, 8, 4))], [square, A(box(4, 4, 8, 8))], [square, A(box(2, 2, 6, 6))],
  [square, A(box(1, 1, 3, 3))], [square, A(box(0, 0, 2, 2))], [holed, A(box(1, 1, 3, 3))], [holed, A(box(1.5, 1.5, 2.5, 2.5))],
  [{ type: "MultiPolygon", coordinates: [[box(0, 0, 1, 1)], [box(2, 2, 3, 3)]] }, A(box(0, 0, 3, 3))],
  [{ type: "MultiLineString", coordinates: [[[0, 0], [1, 1]], [[1, 1], [2, 0]]] }, L([0, 0], [1, 1], [2, 0])],
  [A(ring([[0, 0], [4, 4], [4, 0], [0, 4]])), square], [L([0, 0], [0, 0], [4, 0]), square], [A(box(0, 0, 4, 4), box(0, 0, 4, 4)), square],
];
matrices("hand", hand.map((p) => p[0]), hand.map((p) => p[1]));
matrices("hand reversed", hand.map((p) => p[1]), hand.map((p) => p[0]));

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(19);
const int = (n) => Math.floor(rand() * n);
const pt = () => [int(9), int(9)];
function rectangle() {
  const [x, y] = pt();
  return [x, y, x + 1 + int(4), y + 1 + int(4)];
}
// Valid shapes whose vertices sit on a 9 x 9 grid.
const SHAPES = {
  point: () => P(...pt()),
  multipoint: () => ({ type: "MultiPoint", coordinates: [pt(), pt(), pt()] }),
  line: () => L(...Array.from({ length: 2 + int(3) }, pt)),
  multiline: () => ({ type: "MultiLineString", coordinates: [[pt(), pt()], [pt(), pt(), pt()]] }),
  rectangle: () => A(box(...rectangle())),
  triangle: () => {
    for (;;) {
      const [p, q, s] = [pt(), pt(), pt()];
      const cross = (q[0] - p[0]) * (s[1] - p[1]) - (q[1] - p[1]) * (s[0] - p[0]);
      if (cross !== 0) return A(ring(cross > 0 ? [p, q, s] : [p, s, q]));
    }
  },
  holed: () => {
    const [x, y] = pt();
    const s = 3 + int(3);
    return A(box(x, y, x + s, y + s), box(x + 1, y + 1, x + s - 1, y + s - 1).reverse());
  },
  multipolygon: () => {
    const [x, y] = pt();
    return { type: "MultiPolygon", coordinates: [[box(x, y, x + 1, y + 1)], [box(x + 2, y + int(3), x + 3 + int(2), y + 4)]] };
  },
};
const kinds = Object.keys(SHAPES);
const left = [];
const right = [];
for (let k = 0; k < CASES; k++) {
  left.push(SHAPES[kinds[int(kinds.length)]]());
  right.push(SHAPES[kinds[int(kinds.length)]]());
}
matrices("random", left, right);
for (let k = 0; k < 20; k++) predicates("random sets", left.slice(k * 60, k * 60 + 60), right.slice(k * 60, k * 60 + 60));

// GSI features of a tile: polygons and lines against each other.
const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
let tiles = 0;
for (const x of (await readdir(dir)).sort()) {
  for (const f of (await readdir(path.join(dir, x))).sort()) {
    if (tiles >= TILES) break;
    tiles++;
    const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
    const layer = (name, ok) => {
      const l = tile.layers[name];
      const found = [];
      for (let i = 0; l && i < l.length; i++) {
        const g = l.feature(i).toGeoJSON(Number(x), parseInt(f), 14).geometry;
        if (ok(g.type)) found.push(g);
      }
      return found;
    };
    const areas = (t) => /Polygon/.test(t);
    const lines = (t) => /LineString/.test(t);
    const buildings = layer("building", areas);
    const water = layer("waterarea", areas);
    const roads = layer("road", lines);
    const label = `${x}/${f}`;
    predicates("gsi buildings x roads", buildings, roads, label);
    predicates("gsi water x roads", water, roads, label);
    predicates("gsi roads x roads", roads.slice(0, 200), roads.slice(0, 200), label);
    predicates("gsi buildings x buildings", buildings.slice(0, 200), buildings.slice(0, 200), label);
  }
}

const groups = results;
console.table(groups);
for (const f of failures.slice(0, 10)) console.log(JSON.stringify(f).slice(0, 600));
const ok = failures.length === 0;
await writeFile(path.join(ROOT, "bench/results/relate-golden.json"), JSON.stringify({ jsts: "2.12.1", cases: CASES, tiles: TILES, groups, failures, ok }, null, 2) + "\n");
console.log(ok ? "all identical" : `${failures.length} differ`);
process.exit(ok ? 0 : 1);
