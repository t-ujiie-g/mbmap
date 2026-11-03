import assert from "node:assert/strict";
import test from "node:test";
import { counterClockwise, enoughVertices, finished, geometryOf, rectangleRing } from "../src/draw/shapes.ts";

test("rectangleRing: the four corners from the first, closed", () => {
  assert.deepEqual(rectangleRing([0, 1], [2, 0]), [[0, 1], [2, 1], [2, 0], [0, 0], [0, 1]]);
});

test("geometryOf: each mode's geometry, closing rings, none while too few", () => {
  assert.deepEqual(geometryOf("point", [[1, 2]]), { type: "Point", coordinates: [1, 2] });
  assert.equal(geometryOf("point", []), null);
  assert.equal(geometryOf("linestring", [[0, 0]]), null);
  assert.deepEqual(geometryOf("linestring", [[0, 0], [1, 1]]), { type: "LineString", coordinates: [[0, 0], [1, 1]] });
  assert.deepEqual(geometryOf("polygon", [[0, 0], [1, 0]]), { type: "LineString", coordinates: [[0, 0], [1, 0]] });
  assert.deepEqual(geometryOf("polygon", [[0, 0], [1, 0], [1, 1]]), { type: "Polygon", coordinates: [[[0, 0], [1, 0], [1, 1], [0, 0]]] });
  const ring = rectangleRing([0, 1], [2, 0]);
  assert.deepEqual(geometryOf("rectangle", ring), { type: "Polygon", coordinates: [ring] });
});

test("enoughVertices: two distinct for a line, three for an area", () => {
  assert.equal(enoughVertices("linestring", [[0, 0], [0, 0]]), false);
  assert.equal(enoughVertices("linestring", [[0, 0], [1, 0]]), true);
  assert.equal(enoughVertices("polygon", [[0, 0], [1, 0], [1, 0]]), false);
  assert.equal(enoughVertices("polygon", [[0, 0], [1, 0], [1, 1]]), true);
});

test("counterClockwise: clockwise rings reversed, others kept", () => {
  const ccw: [number, number][] = [[0, 0], [1, 0], [1, 1], [0, 0]];
  assert.equal(counterClockwise(ccw), ccw);
  assert.deepEqual(counterClockwise([[0, 0], [1, 1], [1, 0], [0, 0]]), [[0, 0], [1, 0], [1, 1], [0, 0]]);
});

test("finished: coordinates rounded to 9 decimals, rings counter-clockwise", () => {
  assert.deepEqual(finished({ type: "Point", coordinates: [139.76280846557617, 35.682942933930554] }), { type: "Point", coordinates: [139.762808466, 35.682942934] });
  assert.deepEqual(finished({ type: "LineString", coordinates: [[0.1234567891, 0], [1, 1]] }, 3), { type: "LineString", coordinates: [[0.123, 0], [1, 1]] });
  assert.deepEqual(finished({ type: "Polygon", coordinates: [[[0, 0], [1, 1], [1, 0], [0, 0]]] }), { type: "Polygon", coordinates: [[[0, 0], [1, 0], [1, 1], [0, 0]]] });
});

test("finished: multi geometries rounded too, unknown types kept", () => {
  assert.deepEqual(finished({ type: "MultiPoint", coordinates: [[0.12, 1], [2, 3.456]] }, 1), { type: "MultiPoint", coordinates: [[0.1, 1], [2, 3.5]] });
  assert.deepEqual(finished({ type: "MultiPolygon", coordinates: [[[[0, 0], [1, 1], [1, 0], [0, 0]]]] }), { type: "MultiPolygon", coordinates: [[[[0, 0], [1, 0], [1, 1], [0, 0]]]] });
  assert.deepEqual(finished({ type: "MultiLineString", coordinates: [[[0.04, 0], [1, 1]]] }, 1), { type: "MultiLineString", coordinates: [[[0, 0], [1, 1]]] });
  const other = { type: "GeometryCollection", coordinates: [] };
  assert.equal(finished(other), other);
});
