import assert from "node:assert/strict";
import test from "node:test";
import { readEsri, servicesImports } from "./read.mjs";

test("readEsri refuses what is not bytes of a known format before touching the module", () => {
  const untouched = new Proxy({}, { get: () => assert.fail("the module was used") });
  assert.throws(() => readEsri(untouched, new ArrayBuffer(1), "json"), /invalid arguments/);
  assert.throws(() => readEsri(untouched, new Uint8Array(1), "geojson"), /invalid arguments/);
});

test("servicesImports reads numbers from the instance's memory", () => {
  const memory = new WebAssembly.Memory({ initial: 1 });
  new Uint8Array(memory.buffer).set(new TextEncoder().encode("1.5e-3"), 8);
  assert.equal(servicesImports(() => ({ memory })).host.number(8, 6), 0.0015);
});
