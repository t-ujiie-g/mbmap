import assert from "node:assert/strict";
import test from "node:test";
import { checkColumn, removeColumn, renameColumn, setColumn } from "../src/ui/table-fields.ts";

const features = () => [{ properties: { a: 1, b: "x" } }, { properties: null }, { properties: { b: "y", a: 2 } }];

test("setColumn: sets the features at the indices, adding properties where there were none", () => {
  const fs = features();
  setColumn(fs, "c", [1, 2], [true, undefined]);
  assert.deepEqual(fs, [{ properties: { a: 1, b: "x" } }, { properties: { c: true } }, { properties: { b: "y", a: 2, c: null } }]);
  setColumn(fs, "a", [0], [9]);
  assert.deepEqual(Object.keys(fs[0].properties!), ["a", "b"]);
  assert.equal(fs[0].properties!.a, 9);
});

test("removeColumn: drops the key where it is", () => {
  const fs = features();
  removeColumn(fs, "a");
  assert.deepEqual(fs, [{ properties: { b: "x" } }, { properties: null }, { properties: { b: "y" } }]);
});

test("renameColumn: keeps the key's place, refuses an existing name", () => {
  const fs = features();
  renameColumn(fs, "a", "z");
  assert.deepEqual(fs.map((f) => f.properties && Object.keys(f.properties)), [["z", "b"], null, ["b", "z"]]);
  assert.throws(() => renameColumn(fs, "z", "b"), /exists/);
  renameColumn(fs, "b", "b");
  assert.equal(fs[0].properties!.b, "x");
});

test("checkColumn: refuses empty names, non-strings and __proto__", () => {
  assert.equal(checkColumn("面積"), "面積");
  for (const bad of ["", "__proto__", 1, null]) assert.throws(() => checkColumn(bad), /invalid column/);
  assert.throws(() => setColumn(features(), "__proto__", [0], [1]), /invalid column/);
  assert.throws(() => renameColumn(features(), "a", "__proto__"), /invalid column/);
});
