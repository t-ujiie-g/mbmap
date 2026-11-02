import assert from "node:assert/strict";
import test from "node:test";
import { classifyRings, rangesOf, readFeatureRanges, readQueryResult, toGeometry } from "./query.mjs";

test("classifyRings groups holes with the outer ring before them, as @mapbox/vector-tile", () => {
  const outer = [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]];
  const hole = [[2, 2], [2, 4], [4, 4], [4, 2], [2, 2]];
  const second = [[20, 0], [30, 0], [30, 10], [20, 0]];
  assert.deepEqual(classifyRings([outer, hole, second]), [[outer, hole], [second]]);
  assert.deepEqual(classifyRings([outer]), [[outer]]);
});

test("toGeometry projects tile units to longitude and latitude, single or multi", () => {
  const p = toGeometry(1, [[[2048, 2048]]], 4096, 1, 0, 0);
  assert.deepEqual(p, { type: "Point", coordinates: [-90, 66.51326044311185] });
  assert.equal(toGeometry(1, [[[0, 0]], [[4096, 4096]]], 4096, 0, 0, 0).type, "MultiPoint");
  assert.equal(toGeometry(2, [[[0, 0], [1, 1]], [[2, 2], [3, 3]]], 4096, 0, 0, 0).type, "MultiLineString");
  assert.equal(toGeometry(3, [[[0, 0], [10, 0], [10, 10], [0, 0]]], 4096, 0, 0, 0).type, "Polygon");
});

test("readQueryResult reads records with ids, geometry and prototype-less properties", () => {
  const bytes = [];
  const u8 = (v) => bytes.push(v & 0xff);
  const u32 = (v) => [0, 8, 16, 24].forEach((s) => u8(v >>> s));
  const f64 = (v) => bytes.push(...new Uint8Array(new Float64Array([v]).buffer));
  const str = (s) => { const b = new TextEncoder().encode(s); u32(b.length); bytes.push(...b); };
  u32(1);
  u32(2);
  u32(5);
  f64(NaN);
  u8(3);
  f64(42);
  u8(2);
  u32(4096);
  u32(1);
  u32(2);
  [0, 0, 4096, 4096].forEach(u32);
  u32(2);
  str("__proto__");
  u8(4);
  str("x");
  str("n");
  u8(3);
  f64(1.5);
  const [r] = readQueryResult(new Uint8Array(bytes), 0, 0, 0);
  assert.equal(r.layer, 2);
  assert.equal(r.index, 5);
  assert.ok(Number.isNaN(r.distance));
  assert.equal(r.feature.id, 42);
  assert.equal(r.feature.geometry.type, "LineString");
  assert.deepEqual(r.feature.geometry.coordinates[0], [-180, 85.05112877980659]);
  assert.equal(Object.getPrototypeOf(r.feature.properties), null);
  assert.equal(r.feature.properties.__proto__, "x");
  assert.equal(r.feature.properties.n, 1.5);
});

test("readFeatureRanges keys features by String(id), several per id, and rangesOf picks ids", () => {
  const bytes = [];
  const u8 = (v) => bytes.push(v & 0xff);
  const u32 = (v) => [0, 8, 16, 24].forEach((s) => u8(v >>> s));
  const f64 = (v) => bytes.push(...new Uint8Array(new Float64Array([v]).buffer));
  const str = (s) => { const b = new TextEncoder().encode(s); u32(b.length); bytes.push(...b); };
  u32(2);
  u32(4); // entry 4: id 7 twice, then "a"
  u32(3);
  u8(3); f64(7); u32(0); u32(6);
  u8(3); f64(7); u32(12); u32(3);
  u8(4); str("a"); u32(6); u32(6);
  u32(5); // entry 5: a feature without id
  u32(1);
  u8(0); u32(0); u32(3);
  const ranges = readFeatureRanges(new Uint8Array(bytes));
  assert.deepEqual([...ranges.keys()], [4, 5]);
  assert.deepEqual(ranges.get(4).get("7"), [0, 6, 12, 3]);
  assert.equal(ranges.get(5).size, 0);
  assert.deepEqual(rangesOf(ranges, ["a", "7", "x"]), [{ entry: 4, ranges: [6, 6, 0, 0, 6, 1, 12, 3, 1] }]);
});
