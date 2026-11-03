import assert from "node:assert/strict";
import test from "node:test";
import { checkMaxAngle, clipLine, getAnchors, getCenterAnchor, lineAnchors, mergeLines, tooClose } from "./line-labels.mjs";

const pts = (...xy) => xy.map(([x, y]) => ({ x, y }));

test("lines are cut at the tile's edges, new ends rounded", () => {
  const out = clipLine([pts([-10, 5], [10, 5.4], [20, 30])], 0, 0, 16, 16);
  assert.deepEqual(out, [pts([0, 5], [10, 5.4], [14, 16])]);
  assert.deepEqual(clipLine([pts([20, 20], [30, 30])], 0, 0, 16, 16), []);
});

test("anchors fall every spacing along a line, the first past half the label and 48 glyph units", () => {
  const line = pts([100, 4096], [8000, 4096]);
  const anchors = getAnchors(line, 2000, Math.PI / 4, 10, 8, 1);
  assert.deepEqual(anchors.map((a) => a.x), [524, 2524, 4524, 6524]);
  assert.ok(anchors.every((a) => a.y === 4096 && a.segment === 0 && a.angle === 0));
  // A line coming in from the tile's edge starts half a spacing in.
  assert.deepEqual(getAnchors(pts([0, 10], [5000, 10]), 2000, Math.PI / 4, 10, 8, 1).map((a) => a.x), [1000, 3000]);
});

test("a label may not bend more than the maximum angle under it", () => {
  const line = pts([0, 0], [100, 0], [100, 100]);
  const anchor = { x: 95, y: 0, segment: 0 };
  assert.equal(checkMaxAngle(line, anchor, 40, 30, Math.PI / 4), false);
  assert.equal(checkMaxAngle(line, anchor, 40, 30, Math.PI), true);
  // No room before the start of the line.
  assert.equal(checkMaxAngle(line, { x: 5, y: 0, segment: 0 }, 40, 30, Math.PI), false);
});

test("line-center puts one anchor at the middle of the line", () => {
  const a = getCenterAnchor(pts([0, 0], [100, 0], [100, 50]), Math.PI, 2, 1);
  assert.deepEqual([a.x, a.y, a.segment], [75, 0, 0]);
  assert.equal(getCenterAnchor(pts([0, 0], [10, 0]), Math.PI, 20, 1), null);
});

test("lines with the same text meeting end to start merge, others stay", () => {
  const a = { text: "10", lines: [pts([0, 0], [5, 0])] };
  const b = { text: "10", lines: [pts([5, 0], [9, 3])] };
  const c = { text: "20", lines: [pts([9, 3], [9, 9])] };
  const out = mergeLines([b, c, a]);
  assert.deepEqual(out.map((f) => f.lines[0]), [pts([0, 0], [5, 0], [9, 3]), pts([9, 3], [9, 9])]);
});

test("an anchor near another of the same text is dropped", () => {
  const seen = new Map();
  assert.equal(tooClose(seen, "a", 10, { x: 0, y: 0 }), false);
  assert.equal(tooClose(seen, "a", 10, { x: 6, y: 8 }), false);
  assert.equal(tooClose(seen, "a", 10, { x: 6, y: 7 }), true);
  assert.equal(tooClose(seen, "b", 10, { x: 0, y: 0 }), false);
});

test("deeper tiles get anchors closer together in tile units", () => {
  const lines = [pts([100, 4096], [8000, 4096])];
  const layout = { placement: "line", spacing: 250, maxAngle: 45, size: 12 };
  const at = (overscaling) => lineAnchors(lines, "x", 10, layout, overscaling, new Map()).map((l) => l.anchor.x);
  assert.equal(at(1).length, 2);
  assert.equal(at(2).length, 4);
  assert.ok(lineAnchors(lines, "x", 10, { ...layout, placement: "line-center" }, 1, new Map()).length === 1);
});

test("anchors stop at the limit and a spacing of zero gives none", () => {
  const line = pts([100, 4096], [8000, 4096]);
  assert.deepEqual(getAnchors(line, 2000, Math.PI / 4, 10, 8, 1, 8192, 2).map((a) => a.x), [524, 2524]);
  assert.deepEqual(getAnchors(line, 0, Math.PI / 4, 10, 8, 1), []);
  assert.deepEqual(getAnchors(line, -5, Math.PI / 4, 10, 8, 1), []);
  const layout = { placement: "line", spacing: 250, maxAngle: 45, size: 12 };
  assert.equal(lineAnchors([line], "x", 10, layout, 2, new Map(), 3).length, 3);
  assert.equal(lineAnchors([line], "x", 10, layout, 2, new Map(), 0).length, 0);
  assert.equal(lineAnchors([line, line], "x", 10, { ...layout, placement: "line-center" }, 1, new Map(), 1).length, 1);
});
