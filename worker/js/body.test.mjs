import assert from "node:assert/strict";
import test from "node:test";
import { dataFetchInit, fetchInit, readCapped } from "./body.mjs";

const response = (chunks, headers = {}) => new Response(new ReadableStream({ start(c) { for (const x of chunks) c.enqueue(new Uint8Array(x)); c.close(); } }), { headers });

test("readCapped: joins the chunks of a body within the limit", async () => {
  assert.deepEqual([...(await readCapped(response([[1, 2], [3]]), 3))], [1, 2, 3]);
});

test("readCapped: refuses a body larger than the limit, by its header or as it comes", async () => {
  await assert.rejects(readCapped(response([[1]], { "content-length": "10" }), 4), /larger than 4 bytes/);
  await assert.rejects(readCapped(response([[1, 2], [3, 4], [5]]), 4), /larger than 4 bytes/);
});

test("fetchInit: keeps string headers and a known credentials mode, omits credentials otherwise", () => {
  assert.deepEqual(fetchInit(undefined), { signal: undefined, credentials: "omit" });
  const out = fetchInit({ credentials: "include", headers: { a: "1", b: 2 }, method: "POST" });
  assert.deepEqual(out, { signal: undefined, credentials: "include", headers: { a: "1" } });
  assert.equal(fetchInit({ credentials: "bogus" }).credentials, "omit");
});

test("dataFetchInit: fetchInit with a timeout", () => {
  const out = dataFetchInit({ credentials: "include", headers: { a: "1" } });
  assert.ok(out.signal instanceof AbortSignal);
  assert.equal(out.credentials, "include");
  assert.deepEqual(out.headers, { a: "1" });
});
