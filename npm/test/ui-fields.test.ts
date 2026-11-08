import assert from "node:assert/strict";
import test from "node:test";
import { checkColumn, idsOf, propertiesDiff, removeColumn, renameColumn, setColumn } from "../src/ui/table-fields.ts";

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

test("idsOf: ids by promoteId or the feature's, none when one is missing or repeated", () => {
  assert.deepEqual(idsOf([{ id: 1 }, { id: "a" }]), [1, "a"]);
  assert.deepEqual(idsOf([{ properties: { k: 2 } }, { properties: { k: 3 } }], "k"), [2, 3]);
  assert.equal(idsOf([{ id: 1 }, {}]), undefined);
  assert.equal(idsOf([{ id: 1 }, { id: 1 }]), undefined);
  assert.equal(idsOf([{ id: 1, properties: {} }], "k"), undefined);
});

test("propertiesDiff: the changed features' properties in their order; none when ids changed", () => {
  const fs = [{ id: 1, properties: { a: 1, b: 2 } }, { id: 2, properties: { a: 3 } }];
  renameColumn(fs, "a", "c");
  assert.deepEqual(propertiesDiff(fs, [0], [1, 2]), {
    update: [{ id: 1, removeAllProperties: true, addOrUpdateProperties: [{ key: "c", value: 1 }, { key: "b", value: 2 }] }],
  });
  const promoted = [{ properties: { k: "x", v: 1 } }];
  assert.ok(propertiesDiff(promoted, [0], ["x"], "k"));
  renameColumn(promoted, "k", "j");
  assert.equal(propertiesDiff(promoted, [0], ["x"], "k"), undefined);
});
