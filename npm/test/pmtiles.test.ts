import assert from "node:assert/strict";
import test from "node:test";
import { headerDocument, pmtilesDocument } from "../src/pmtiles.ts";

const header = new Uint8Array(127);
header.set([..."PMTiles"].map((c) => c.charCodeAt(0)));
header[7] = 3;
header[99] = 1;
header[100] = 2;
header[101] = 14;

function serve(status: number, body: Uint8Array, length = body.length) {
  globalThis.fetch = async () => new Response(body, { status, headers: { "content-length": String(length) } });
}

test("pmtilesDocument reads the header from a range answer", async (t) => {
  const real = globalThis.fetch;
  t.after(() => (globalThis.fetch = real));
  serve(206, header);
  const doc = await pmtilesDocument("https://x.test/a.pmtiles");
  assert.deepEqual([doc.minzoom, doc.maxzoom, doc.tileType], [2, 14, "mvt"]);
  assert.deepEqual(doc.tiles, ["pmtiles://https://x.test/a.pmtiles/{z}/{x}/{y}"]);
});

test("pmtilesDocument refuses a server that ignores Range and sends the whole archive", async (t) => {
  const real = globalThis.fetch;
  t.after(() => (globalThis.fetch = real));
  serve(200, new Uint8Array(4096));
  await assert.rejects(pmtilesDocument("https://x.test/a.pmtiles"), /answered 200 to a range request/);
  // A 206 that says it is small but is not is cut at the range's length.
  serve(206, new Uint8Array(4096), 127);
  await assert.rejects(pmtilesDocument("https://x.test/a.pmtiles"), /larger than 127 bytes/);
  serve(404, new Uint8Array(0));
  await assert.rejects(pmtilesDocument("https://x.test/a.pmtiles"), /answered 404/);
});

test("headerDocument reads zooms, bounds and the tile type of a v3 header", () => {
  const h = header.slice();
  const v = new DataView(h.buffer);
  [1395000000, 356000000, 1396000000, 357000000].forEach((d, i) => v.setInt32(102 + 4 * i, d, true));
  h[99] = 2;
  assert.deepEqual(headerDocument("https://x.test/a.pmtiles", h), {
    tiles: ["pmtiles://https://x.test/a.pmtiles/{z}/{x}/{y}"],
    minzoom: 2,
    maxzoom: 14,
    bounds: [139.5, 35.6, 139.6, 35.7],
    tileType: "png",
  });
  h[99] = 9;
  assert.equal(headerDocument("a", h).tileType, "unknown");
});

test("headerDocument refuses a header too short, another magic and other versions", () => {
  assert.throws(() => headerDocument("https://x.test/a", header.subarray(0, 126)), /mbmap: https:\/\/x.test\/a is not a PMTiles v3 archive/);
  const other = header.slice();
  other[0] = 0x51;
  assert.throws(() => headerDocument("a", other), /not a PMTiles v3 archive/);
  const v2 = header.slice();
  v2[7] = 2;
  assert.throws(() => headerDocument("a", v2), /not a PMTiles v3 archive/);
});
