import assert from "node:assert/strict";
import test from "node:test";
import { bboxOf, choose, noDataOf, originOf, resample, resolutionOf } from "./geotiff.mjs";

const image = (over) => ({ width: 100, height: 50, pixelScale: [], tiepoint: [], transform: [], subfile: 0, oldSubfile: 0, ...over });
const first = image({ pixelScale: [0.5, 0.25, 0], tiepoint: [0, 0, 0, 10, 20, 0] });
const half = image({ width: 50, height: 25, subfile: 1 });
const mask = image({ width: 25, height: 12, subfile: 4 });

test("origin, resolution and bbox follow geotiff's tags", () => {
  assert.deepEqual(originOf(first), [10, 20, 0]);
  assert.deepEqual(resolutionOf(first), [0.5, -0.25, 0]);
  assert.deepEqual(resolutionOf(half, first), [1, -0.5, 0]);
  assert.deepEqual(bboxOf(first), [10, 7.5, 60, 20]);
  const t = image({ transform: [0, 0.5, 0, 10, 0.25, 0, 0, 20, 0, 0, 0, 0, 0, 0, 0, 1] });
  assert.deepEqual(bboxOf(t), [10, 20, 35, 45]);
  assert.throws(() => originOf(half), /affine transformation/);
  assert.equal(noDataOf({ nodata: "-9999\0" }), -9999);
  assert.equal(noDataOf({ nodata: null }), null);
});

test("choose picks the coarsest image still fine enough, and rounds a bbox to a window", () => {
  const images = [first, half, mask];
  assert.deepEqual(choose(images, {}), { index: 0, window: [0, 0, 100, 50] });
  assert.deepEqual(choose(images, { width: 50 }), { index: 0, window: [0, 0, 100, 50] });
  assert.deepEqual(choose(images, { width: 20 }), { index: 1, window: [0, 0, 50, 25] });
  assert.deepEqual(choose(images, { bbox: [11, 15, 13, 19] }), { index: 0, window: [2, 4, 6, 20] });
  assert.deepEqual(choose(images, { image: 1, window: [1, 2, 3, 4] }), { index: 1, window: [1, 2, 3, 4] });
  assert.throws(() => choose(images, { window: [0, 0, 1, 1], bbox: [0, 0, 1, 1] }), /Both "bbox" and "window"/);
  assert.throws(() => choose(images, { window: [2, 0, 1, 1] }), /Invalid subsets/);
  assert.throws(() => choose(images, { image: 3 }), /no image 3/);
});

test("resample matches geotiff's nearest and bilinear", () => {
  const band = Float32Array.from([0, 1, 2, 3]);
  assert.deepEqual(Array.from(resample([band], 2, 2, 4, 4)[0]), [0, 1, 1, 1, 2, 3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3]);
  assert.deepEqual(Array.from(resample([band], 2, 2, 4, 1, "bilinear")[0]), [0, 0.5, 1, 1]);
  assert.equal(resample([Uint8Array.from([1, 2])], 2, 1, 1, 1)[0].constructor, Uint8Array);
  assert.throws(() => resample([band], 2, 2, 1, 1, "cubic"), /Unsupported resampling method/);
});
