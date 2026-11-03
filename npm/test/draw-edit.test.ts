import assert from "node:assert/strict";
import test from "node:test";
import { deleteVertex, insertVertex, insideRing, midpoints, moveVertex, nearestOnSegment, translate, vertices } from "../src/draw/edit.ts";

const square = { type: "Polygon", coordinates: [[[0, 0], [2, 0], [2, 2], [0, 2], [0, 0]]] };
const line = { type: "LineString", coordinates: [[0, 0], [1, 0], [2, 1]] };

test("vertices: each once, a ring's closing copy left out", () => {
  assert.deepEqual(vertices(square).map((v) => v.at), [0, 1, 2, 3].map((index) => ({ ring: 0, index })));
  assert.deepEqual(vertices({ type: "Point", coordinates: [5, 6] }), [{ at: { ring: 0, index: 0 }, position: [5, 6] }]);
});

test("midpoints: one per edge, inserting before the edge's end", () => {
  assert.deepEqual(midpoints(line), [{ at: { ring: 0, index: 1 }, position: [0.5, 0] }, { at: { ring: 0, index: 2 }, position: [1.5, 0.5] }]);
  assert.equal(midpoints(square).length, 4);
  assert.deepEqual(midpoints({ type: "Point", coordinates: [0, 0] }), []);
});

test("moveVertex: a ring's first vertex moves its closing copy", () => {
  assert.deepEqual(moveVertex(square, { ring: 0, index: 0 }, [-1, -1]).coordinates, [[[-1, -1], [2, 0], [2, 2], [0, 2], [-1, -1]]]);
  assert.deepEqual(moveVertex(line, { ring: 0, index: 2 }, [3, 3]).coordinates, [[0, 0], [1, 0], [3, 3]]);
  assert.deepEqual(moveVertex({ type: "Point", coordinates: [0, 0] }, { ring: 0, index: 0 }, [1, 1]), { type: "Point", coordinates: [1, 1] });
});

test("insertVertex and deleteVertex keep lines at 2 vertices and rings at 3", () => {
  const five = insertVertex(square, { ring: 0, index: 1 }, [1, -1]);
  assert.deepEqual(five.coordinates, [[[0, 0], [1, -1], [2, 0], [2, 2], [0, 2], [0, 0]]]);
  assert.deepEqual(deleteVertex(five, { ring: 0, index: 0 })?.coordinates, [[[1, -1], [2, 0], [2, 2], [0, 2], [1, -1]]]);
  const triangle = deleteVertex(square, { ring: 0, index: 3 })!;
  assert.equal(deleteVertex(triangle, { ring: 0, index: 0 }), null);
  assert.deepEqual(deleteVertex(line, { ring: 0, index: 1 })?.coordinates, [[0, 0], [2, 1]]);
  assert.equal(deleteVertex({ type: "LineString", coordinates: [[0, 0], [1, 1]] }, { ring: 0, index: 0 }), null);
  assert.equal(deleteVertex({ type: "Point", coordinates: [0, 0] }, { ring: 0, index: 0 }), null);
});

test("translate moves every vertex", () => {
  assert.deepEqual(translate(line, 1, -1).coordinates, [[1, -1], [2, -1], [3, 0]]);
});

test("nearestOnSegment and insideRing on screen points", () => {
  assert.deepEqual(nearestOnSegment({ x: 5, y: 5 }, { x: 0, y: 0 }, { x: 10, y: 0 }), { x: 5, y: 0, t: 0.5 });
  assert.deepEqual(nearestOnSegment({ x: -5, y: 1 }, { x: 0, y: 0 }, { x: 10, y: 0 }), { x: 0, y: 0, t: 0 });
  assert.deepEqual(nearestOnSegment({ x: 1, y: 1 }, { x: 2, y: 2 }, { x: 2, y: 2 }), { x: 2, y: 2, t: 0 });
  const box = [{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 10 }, { x: 0, y: 10 }, { x: 0, y: 0 }];
  assert.equal(insideRing({ x: 5, y: 5 }, box), true);
  assert.equal(insideRing({ x: 15, y: 5 }, box), false);
});
