import assert from "node:assert/strict";
import test from "node:test";
import { pmtilesDocument } from "../src/pmtiles.ts";

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
