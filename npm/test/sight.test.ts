import assert from "node:assert/strict";
import test from "node:test";
import { CURVATURE_COEFF, EARTH_RADIUS, groundDistance, sight } from "../src/sight.ts";

const flat = (n: number, step: number) => Array.from({ length: n }, (_, i) => i * step);

test("sight sees over flat ground and is hidden by a ridge, with the first sample that hides it", () => {
  assert.deepEqual(sight([10, 10, 10, 10, 10], flat(5, 100), 2, 0, 0), { visible: true, blockedAt: null });
  assert.deepEqual(sight([10, 10, 50, 60, 10], flat(5, 100), 2, 0, 0), { visible: false, blockedAt: 2 });
  // A target raised above the ridge's line is seen.
  assert.deepEqual(sight([10, 10, 50, 10, 10], flat(5, 100), 2, 200, 0).visible, true);
  // NaN heights hide nothing.
  assert.deepEqual(sight([10, Number.NaN, 10], flat(3, 100)), { visible: true, blockedAt: null });
});

test("sight lowers far ground by the earth's curvature as gdal_viewshed does", () => {
  // 20 km of sea: the far target at 0 m drops below the observer's horizon only with curvature.
  const d = flat(201, 100);
  const sea = d.map(() => 0);
  assert.equal(sight(sea, d, 2, 0, 0).visible, true);
  const drop = (CURVATURE_COEFF / (2 * 6378137)) * 20000 ** 2;
  assert.ok(drop > 26 && drop < 28);
  assert.equal(sight(sea, d, 2, 0).visible, false);
  assert.equal(sight(sea, d, 2, drop).visible, true);
});

test("sight refuses fewer than two samples or mismatched distances", () => {
  assert.throws(() => sight([1], [0]), /two or more samples/);
  assert.throws(() => sight([1, 2], [0]), /two or more samples/);
});

test("groundDistance measures on Turf's sphere", () => {
  assert.equal(groundDistance([0, 0], [0, 0]), 0);
  assert.ok(Math.abs(groundDistance([0, 0], [1, 0]) - (Math.PI / 180) * EARTH_RADIUS) < 1e-6);
});
