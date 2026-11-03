import assert from "node:assert/strict";
import test from "node:test";
import { checkBlobImageSize, checkImageSize, imageSize } from "./imagesize.mjs";

const bytes = (...parts) => new Uint8Array(parts.flatMap((p) => (typeof p === "string" ? [...p].map((c) => c.charCodeAt(0)) : [...p])));
const be32 = (v) => [v >>> 24, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
const be16 = (v) => [v >> 8, v & 255];
const le16 = (v) => [v & 255, v >> 8];
const le24 = (v) => [v & 255, (v >> 8) & 255, v >> 16];

const png = (w, h) => bytes([0x89], "PNG\r\n\x1a\n", be32(13), "IHDR", be32(w), be32(h), [8, 6, 0, 0, 0]);
// SOI, an APP0 segment of 16 bytes, then `sof` with its height and width.
const jpeg = (w, h, sof = 0xc0) => bytes([0xff, 0xd8, 0xff, 0xe0], be16(16), new Array(14).fill(0), [0xff, sof], be16(17), [8], be16(h), be16(w), [3]);
const webp = (chunk, payload) => bytes("RIFF", [0, 0, 0, 0], "WEBP", chunk, [0, 0, 0, 0], payload);

test("imageSize reads PNG's IHDR", () => {
  assert.deepEqual(imageSize(png(256, 512)), { width: 256, height: 512 });
  assert.deepEqual(imageSize(png(0x7fffffff, 1)), { width: 0x7fffffff, height: 1 });
});

test("imageSize walks JPEG segments to the first SOF, padding and RST markers included", () => {
  assert.deepEqual(imageSize(jpeg(640, 480)), { width: 640, height: 480 });
  assert.deepEqual(imageSize(jpeg(65535, 3, 0xc2)), { width: 65535, height: 3 });
  const padded = bytes([0xff, 0xd8, 0xff, 0xff, 0xd0], jpeg(9, 8).subarray(2));
  assert.deepEqual(imageSize(padded), { width: 9, height: 8 });
  // A DHT (C4) segment is not a frame.
  const dht = bytes([0xff, 0xd8, 0xff, 0xc4], be16(6), [1, 2, 3, 4], jpeg(5, 6).subarray(2));
  assert.deepEqual(imageSize(dht), { width: 5, height: 6 });
  assert.equal(imageSize(bytes([0xff, 0xd8, 0xff, 0xda], be16(12), new Array(12).fill(0))), null);
  assert.equal(imageSize(bytes([0xff, 0xd8, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0])), null);
  assert.equal(imageSize(jpeg(1, 1).subarray(0, 24)), null);
});

test("imageSize reads WebP's VP8, VP8L and VP8X headers", () => {
  assert.deepEqual(imageSize(webp("VP8 ", [0, 0, 0, 0x9d, 0x01, 0x2a, ...le16(300 | 0x4000), ...le16(200), 0, 0])), { width: 300, height: 200 });
  const bits = (16383 - 1) | ((7 - 1) << 14);
  assert.deepEqual(imageSize(webp("VP8L", [0x2f, bits & 255, (bits >> 8) & 255, (bits >> 16) & 255, bits >>> 24, 0, 0, 0, 0, 0])), { width: 16383, height: 7 });
  assert.deepEqual(imageSize(webp("VP8X", [0, 0, 0, 0, ...le24(70000 - 1), ...le24(2 - 1)])), { width: 70000, height: 2 });
  assert.equal(imageSize(webp("ALPH", new Array(10).fill(0))), null);
});

const box = (type, ...contents) => {
  const body = bytes(...contents);
  return bytes(be32(8 + body.length), type, body);
};
const avif = bytes(box("ftyp", "avifmif1"), box("meta", [0, 0, 0, 0], box("iprp", box("ipco", box("ispe", [0, 0, 0, 0], be32(256), be32(256))))));

test("imageSize gives null for GIF, AVIF, other or truncated data", () => {
  assert.equal(imageSize(bytes("GIF89a", le16(320), le16(240))), null);
  assert.equal(imageSize(avif), null);
  assert.equal(imageSize(bytes("BM", new Array(30).fill(0))), null);
  assert.equal(imageSize(png(1, 1).subarray(0, 20)), null);
  assert.equal(imageSize(new Uint8Array(0)), null);
});

test("checkImageSize refuses a side over the cap and anything it cannot size", () => {
  checkImageSize(png(4096, 4096), 4096);
  assert.throws(() => checkImageSize(png(4097, 1), 4096, "raster tile"), /raster tile is 4097 x 1, over 4096/);
  assert.throws(() => checkImageSize(jpeg(1, 60000), 8192), /over 8192/);
  assert.throws(() => checkImageSize(avif, 4096, "raster tile"), /raster tile: not a PNG, JPEG or WebP/);
  assert.throws(() => checkImageSize(bytes("GIF89a", le16(1), le16(1)), 4096), /not a PNG/);
  assert.throws(() => checkImageSize(bytes("not an image"), 4096, "raster tile"), /raster tile: not a PNG, JPEG or WebP/);
  assert.throws(() => checkImageSize(new Uint8Array(0), 4096), /not a PNG/);
});

test("checkBlobImageSize reads a Blob's header and refuses a JPEG without a SOF in it", async () => {
  await checkBlobImageSize(new Blob([png(8192, 8192)]), 8192);
  await assert.rejects(checkBlobImageSize(new Blob([png(1, 100000)]), 8192, "sprite"), /sprite is 1 x 100000/);
  // APP segments of 64 KB each push the SOF past the bytes read.
  const app = bytes([0xff, 0xe1], be16(0xffff), new Array(0xfffd).fill(0));
  const late = new Blob([bytes([0xff, 0xd8]), app, app, app, app, app, jpeg(9, 9).subarray(2)]);
  await assert.rejects(checkBlobImageSize(late, 8192, "image"), /image: not a PNG/);
  await checkBlobImageSize(new Blob([bytes([0xff, 0xd8]), app, jpeg(9, 9).subarray(2)]), 8192);
});
