import assert from "node:assert/strict";
import test from "node:test";
import { deflateSync } from "node:zlib";
import { decodePng } from "./png.mjs";

// A PNG of `rows` (RGB bytes per row), each row with its own filter byte.
function png(width, rows, filters) {
  const chunk = (type, data) => {
    const head = Buffer.alloc(8);
    head.writeUInt32BE(data.length, 0);
    head.write(type, 4, "latin1");
    return Buffer.concat([head, data, Buffer.alloc(4)]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(rows.length, 4);
  ihdr.set([8, 2, 0, 0, 0], 8);
  const raw = Buffer.concat(rows.map((r, y) => Buffer.from([filters[y], ...r])));
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

test("RGB rows decode through every filter type into RGBA", () => {
  // Row 0 raw; row 1 Sub (+left); row 2 Up (+above); row 3 Average; row 4 Paeth.
  const rows = [[10, 20, 30, 1, 2, 3], [5, 5, 5, 1, 1, 1], [1, 1, 1, 2, 2, 2], [0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0]];
  const { width, height, rgba } = decodePng(png(2, rows, [0, 1, 2, 3, 4]));
  assert.deepEqual([width, height], [2, 5]);
  const px = (x, y) => [...rgba.subarray((y * 2 + x) * 4, (y * 2 + x) * 4 + 4)];
  assert.deepEqual(px(0, 0), [10, 20, 30, 255]);
  assert.deepEqual(px(1, 1), [6, 6, 6, 255]);
  assert.deepEqual(px(0, 2), [6, 6, 6, 255]);
  // Average: (left + above) / 2, left 0 at x 0: (0 + 6) / 2, then (3 + 8) / 2.
  assert.deepEqual(px(0, 3), [3, 3, 3, 255]);
  assert.deepEqual(px(1, 3), [5, 5, 5, 255]);
  // Paeth picks the neighbour nearest left + above - upper left: above both times.
  assert.deepEqual(px(0, 4), [3, 3, 3, 255]);
  assert.deepEqual(px(1, 4), [5, 5, 5, 255]);
  assert.throws(() => decodePng(Buffer.from("nope")));
});
