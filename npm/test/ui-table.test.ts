import assert from "node:assert/strict";
import test from "node:test";
import { boxOf } from "../src/search/dataset.ts";
import { cellText, columnsOf, featuresOf, filterRows, pageOf, rowsOf, sortRows, type TableRow } from "../src/ui/table-rows.ts";

const point = (x: number, y: number) => ({ type: "Point", coordinates: [x, y] });
const row = (id: number, properties: Record<string, unknown>): TableRow => ({ id, properties, geometry: null });
const collator = new Intl.Collator("ja", { numeric: true });

test("featuresOf: a collection's features, or the feature itself; nothing without data", () => {
  const f = { type: "Feature", properties: { a: 1 }, geometry: point(1, 2) };
  assert.deepEqual(featuresOf({ type: "FeatureCollection", features: [f, f] }), [f, f]);
  assert.deepEqual(featuresOf(f), [f]);
  assert.deepEqual(featuresOf(null), []);
});

test("rowsOf: ids from the feature or a property; pieces of one id become one row, boxed whole", () => {
  const a = { type: "LineString", coordinates: [[0, 0], [1, 1]] };
  const b = { type: "LineString", coordinates: [[1, 1], [3, -2]] };
  const rows = rowsOf([
    { id: 7, properties: { name: "a" }, geometry: a },
    { id: 7, properties: { name: "a" }, geometry: b },
    { id: 7, properties: { name: "a" }, geometry: point(-1, 0) },
    { properties: { name: "b" }, geometry: point(5, 5) },
    { properties: { name: "b" }, geometry: null },
    { id: 0, properties: null },
  ]);
  assert.deepEqual(rows, [
    { id: 7, properties: { name: "a" }, geometry: { type: "GeometryCollection", geometries: [{ type: "GeometryCollection", geometries: [a, b] }, point(-1, 0)] } },
    { id: null, properties: { name: "b" }, geometry: point(5, 5) },
    { id: null, properties: { name: "b" }, geometry: null },
    { id: 0, properties: {}, geometry: null },
  ]);
  assert.deepEqual(boxOf(rows[0].geometry), [-1, -2, 3, 1]);
  assert.equal(boxOf(rows[2].geometry), null);
  const promoted = rowsOf([{ id: 1, properties: { name: "東京駅" } }, { properties: { name: "上野駅" } }, { properties: {} }], "name");
  assert.deepEqual(promoted.map((r) => r.id), ["東京駅", "上野駅", null]);
});

test("columnsOf: every key in the order first seen", () => {
  assert.deepEqual(columnsOf([row(1, { b: 1, a: 2 }), row(2, { c: 3, a: 4 }), row(3, {})]), ["b", "a", "c"]);
});

test("cellText: empty for missing values, JSON for objects", () => {
  assert.deepEqual([null, undefined, 0, "x", true, [1, 2], { a: 1 }].map(cellText), ["", "", "0", "x", "true", "[1,2]", '{"a":1}']);
});

test("sortRows: numbers, then text by the numeric collator, then missing values; stable", () => {
  const rows = [row(1, { v: "駅10" }), row(2, { v: 3 }), row(3, {}), row(4, { v: "駅9" }), row(5, { v: null }), row(6, { v: 3 }), row(7, { v: -1 }), row(8, { v: "a" })];
  assert.deepEqual(sortRows(rows, "v", "asc", collator).map((r) => r.id), [7, 2, 6, 8, 4, 1, 3, 5]);
  assert.deepEqual(sortRows(rows, "v", "desc", collator).map((r) => r.id), [2, 6, 7, 1, 4, 8, 3, 5]);
  assert.deepEqual(rows.map((r) => r.id), [1, 2, 3, 4, 5, 6, 7, 8]);
});

test("filterRows: the query folded by width, case and kana in the chosen columns, and the predicate", () => {
  const rows = [row(1, { name: "トウキョウ", n: 1 }), row(2, { name: "ＡＢＣ", n: 2 }), row(3, { name: "abc", kind: "x", n: 3 }), row(4, { kind: "abc" })];
  assert.deepEqual(filterRows(rows, "とうきょう", ["name"]).map((r) => r.id), [1]);
  assert.deepEqual(filterRows(rows, " Abc ", ["name"]).map((r) => r.id), [2, 3]);
  assert.deepEqual(filterRows(rows, "abc", ["name", "kind"]).map((r) => r.id), [2, 3, 4]);
  assert.deepEqual(filterRows(rows, "", ["name"], (r) => Number(r.properties.n) >= 2).map((r) => r.id), [2, 3]);
  assert.deepEqual(filterRows(rows, "abc", ["name"], (r) => r.id === 3).map((r) => r.id), [3]);
});

test("pageOf: pages clamped, at least one", () => {
  assert.deepEqual(pageOf(21, 0, 10), { page: 0, pages: 3 });
  assert.deepEqual(pageOf(21, 2, 10), { page: 2, pages: 3 });
  assert.deepEqual(pageOf(21, 9, 10), { page: 2, pages: 3 });
  assert.deepEqual(pageOf(21, -1, 10), { page: 0, pages: 3 });
  assert.deepEqual(pageOf(0, 3, 10), { page: 0, pages: 1 });
  assert.deepEqual(pageOf(5, Number.NaN, 2), { page: 0, pages: 3 });
});
