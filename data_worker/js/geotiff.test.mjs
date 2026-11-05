import assert from "node:assert/strict";
import test from "node:test";
import { deflateSync } from "node:zlib";
import { bboxOf, choose, noDataOf, originOf, readRaster, resample, resolutionOf } from "./geotiff.mjs";

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

// A "GeoTIFF images" summary of one 8-bit image of 64-pixel blocks, `blocks` of them in a column.
function summary({ blocks = 1, compression = 1, count = 0 }) {
  const out = [];
  const u32 = (v) => out.push(...new Uint8Array(Uint32Array.of(v).buffer));
  const doubles = (a) => {
    u32(a.length);
    out.push(...new Uint8Array(Float64Array.from(a).buffer));
  };
  u32(1);
  u32(1);
  [64, 64 * blocks, 1, 64, 64, 1, 1, compression, 1, -1, 0, 0, 0, 0].forEach((v) => u32(v >>> 0));
  u32(8);
  u32(1);
  doubles([]);
  doubles([]);
  doubles([]);
  doubles(Array(blocks).fill(0));
  doubles(Array(blocks).fill(count));
  out.push(0);
  u32(0xffffffff);
  while (out.length % 4) out.push(0);
  return Uint8Array.from(out).buffer;
}

// A stand-in for geotiff.wasm that takes every block and answers with `images`.
const context = (images, max) => ({
  max,
  input() {},
  output: (_, n) => (n === 1 ? images : new ArrayBuffer(1 << 20)),
  wasm: { parse: () => 1, window: () => 0, block: () => 0, empty: () => 0, bands: () => 0 },
});

test("a read stops once its blocks would decode past 8 times the limit", async () => {
  const stream = new Uint8Array(deflateSync(new Uint8Array(4096)));
  const ctx = context(summary({ blocks: 20, compression: 8, count: stream.length }), 5000);
  const raster = await readRaster({ bytes: stream }, { window: [0, 0, 64, 64 * 9] }, ctx);
  assert.equal(raster.height, 64 * 9);
  await assert.rejects(readRaster({ bytes: stream }, { window: [0, 0, 64, 64 * 20] }, ctx), /blocks decoding to more than 40000 bytes/);
});

test("a WebP block larger than the image's blocks is refused before it reaches a canvas", async (t) => {
  let closed = false;
  globalThis.createImageBitmap = async () => ({ width: 8192, height: 64, close: () => (closed = true) });
  t.after(() => delete globalThis.createImageBitmap);
  const ctx = context(summary({ compression: 50001, count: 4 }), 1 << 20);
  await assert.rejects(readRaster({ bytes: new Uint8Array(4) }, {}, ctx), /a block's picture of 8192 x 64 pixels/);
  assert.ok(closed);
});

test("files kept by URL are dropped past the limit in bytes, oldest first, but for the newest", async () => {
  const ctx = context(summary({}), 1000);
  const reads = [];
  const read = (key, size) => readRaster({ key, read: async () => (reads.push(key), { whole: new Uint8Array(size) }) }, {}, ctx);
  await read("kept a", 400);
  await read("kept b", 400);
  await read("kept c", 400);
  await read("kept c", 400);
  await read("kept b", 400);
  assert.deepEqual(reads, ["kept a", "kept b", "kept c"]);
  await read("kept a", 400);
  assert.equal(reads.length, 4);
  await read("kept large", 3000);
  await read("kept large", 3000);
  assert.equal(reads.length, 5);
  await read("kept b", 400);
  assert.equal(reads.length, 6);
});
