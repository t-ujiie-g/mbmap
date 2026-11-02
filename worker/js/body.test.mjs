import assert from "node:assert/strict";
import test from "node:test";
import { readCapped } from "./body.mjs";

const response = (chunks, headers = {}) => new Response(new ReadableStream({ start(c) { for (const x of chunks) c.enqueue(new Uint8Array(x)); c.close(); } }), { headers });

test("readCapped: joins the chunks of a body within the limit", async () => {
  assert.deepEqual([...(await readCapped(response([[1, 2], [3]]), 3))], [1, 2, 3]);
});

test("readCapped: refuses a body larger than the limit, by its header or as it comes", async () => {
  await assert.rejects(readCapped(response([[1]], { "content-length": "10" }), 4), /larger than 4 bytes/);
  await assert.rejects(readCapped(response([[1, 2], [3, 4], [5]]), 4), /larger than 4 bytes/);
});
