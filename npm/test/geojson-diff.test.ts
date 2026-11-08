import assert from "node:assert/strict";
import test from "node:test";
import { applySourceDiff, geometryBounds, isSourceDiff, mergeSourceDiffs, tileMeets, toUpdateable } from "../src/geojson-diff.ts";

const point = (id: unknown, x: number, y: number, properties: Record<string, unknown> = {}) => ({
  type: "Feature",
  id,
  properties,
  geometry: { type: "Point", coordinates: [x, y] },
});

test("toUpdateable takes features with ids of their own, or of promoteId", () => {
  assert.equal(toUpdateable(null)?.size, 0);
  assert.equal(toUpdateable({})?.size, 0);
  assert.deepEqual([...toUpdateable(point(0, 1, 2))!.keys()], [0]);
  const fc = { type: "FeatureCollection", features: [point("a", 0, 0), point(2, 1, 1)] };
  assert.deepEqual([...toUpdateable(fc)!.keys()], ["a", 2]);
  assert.equal(toUpdateable({ type: "FeatureCollection", features: [point("a", 0, 0), point("a", 1, 1)] }), undefined);
  assert.equal(toUpdateable({ type: "FeatureCollection", features: [point(undefined, 0, 0)] }), undefined);
  assert.equal(toUpdateable(point(null, 0, 0)), undefined);
  assert.equal(toUpdateable({ type: "Point", coordinates: [0, 0] }), undefined);
  assert.equal(toUpdateable({ type: "FeatureCollection", features: 3 }), undefined);
  const named = { type: "FeatureCollection", features: [point(undefined, 0, 0, { name: "x" }), { type: "Feature", properties: null, geometry: null }] };
  assert.equal(toUpdateable(named, "name"), undefined);
  assert.deepEqual([...toUpdateable({ ...named, features: [named.features[0]] }, "name")!.keys()], ["x"]);
});

test("applySourceDiff removes, adds and updates in MapLibre's order, copying only the features it changes", () => {
  const a = point("a", 0, 0, { k: 1 });
  const b = point("b", 1, 1, { k: 2, j: 3 });
  const features = toUpdateable({ type: "FeatureCollection", features: [a, b] })!;
  const affected = applySourceDiff(features, {
    remove: ["a", "missing"],
    add: [point("c", 2, 2)],
    update: [
      { id: "b", removeProperties: ["j"], addOrUpdateProperties: [{ key: "k", value: 5 }, { key: "__proto__", value: { polluted: true } }] },
      { id: "missing", newGeometry: { type: "Point", coordinates: [9, 9] } },
      { id: "c" },
    ],
  });
  assert.deepEqual([...features.keys()], ["b", "c"]);
  assert.deepEqual(affected, [a.geometry, { type: "Point", coordinates: [2, 2] }, b.geometry]);
  const nb = features.get("b")!;
  assert.notEqual(nb, b);
  assert.deepEqual(b.properties, { k: 2, j: 3 });
  assert.equal(nb.properties!.k, 5);
  assert.equal(Object.getPrototypeOf(nb.properties), Object.prototype);
  assert.equal(JSON.stringify(nb.properties), '{"k":5,"__proto__":{"polluted":true}}');
  assert.deepEqual(applySourceDiff(features, { removeAll: true, remove: ["b"] }), []);
  assert.equal(features.size, 0);
});

test("mergeSourceDiffs squashes a removal followed by an add and merges updates of one feature", () => {
  const merged = mergeSourceDiffs(
    { remove: ["a"], update: [{ id: "b", addOrUpdateProperties: [{ key: "x", value: 1 }, { key: "y", value: 2 }] }] },
    { add: [point("a", 0, 0)], update: [{ id: "b", removeProperties: ["x"], newGeometry: { type: "Point", coordinates: [1, 1] } }] },
  );
  assert.deepEqual(merged, {
    remove: [],
    add: [point("a", 0, 0)],
    update: [{ id: "b", removeProperties: ["x"], addOrUpdateProperties: [{ key: "y", value: 2 }], newGeometry: { type: "Point", coordinates: [1, 1] } }],
  });
  assert.deepEqual(mergeSourceDiffs({ add: [point("a", 0, 0)] }, { removeAll: true }), { removeAll: true, remove: [], add: [], update: [] });
  assert.deepEqual(mergeSourceDiffs(undefined, { remove: [1] }), { remove: [1] });
});

test("isSourceDiff refuses what is not MapLibre's diff", () => {
  assert.ok(isSourceDiff({}));
  assert.ok(isSourceDiff({ remove: [1], add: [point(1, 0, 0)], update: [{ id: 1 }] }));
  for (const bad of [null, 3, { remove: 1 }, { add: [null] }, { update: "x" }]) assert.equal(isSourceDiff(bad), false);
});

test("geometryBounds gives a box per geometry with positions", () => {
  const bounds = geometryBounds([
    { type: "LineString", coordinates: [[1, 2], [3, -4]] },
    null,
    { type: "Polygon", coordinates: [] },
    { type: "GeometryCollection", geometries: [{ type: "Point", coordinates: [5, 6] }, { type: "MultiPoint", coordinates: [[-1, 0]] }] },
  ]);
  assert.deepEqual(bounds, [1, -4, 3, 2, -1, 0, 5, 6]);
});

test("tileMeets grows the tile by its buffer, counts touching and wraps the antimeridian", () => {
  assert.ok(tileMeets(0, [10, 10, 10, 10], 1, 1, 0));
  assert.ok(tileMeets(0, [0, 10, 0, 10], 1, 1, 0));
  assert.ok(!tileMeets(0, [10, -10, 10, -10], 1, 1, 0));
  assert.ok(tileMeets(0.25, [10, -10, 10, -10], 1, 1, 0));
  assert.ok(!tileMeets(0.25, [10, -50, 10, -50], 1, 1, 0));
  assert.ok(!tileMeets(0, [-160, 10, -160, 10], 1, 1, 0));
  assert.ok(tileMeets(0.25, [-160, 10, -160, 10], 1, 1, 0));
  assert.ok(tileMeets(0, [170, 0, -170, 10], 1, 1, 0));
  assert.ok(tileMeets(0, [-400, 10, 400, 10], 1, 1, 0));
  assert.ok(tileMeets(0, [-50, -50, -50, -50, 10, 10, 20, 20], 1, 1, 0));
  assert.ok(!tileMeets(0, [], 1, 1, 0));
});
