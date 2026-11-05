import assert from "node:assert/strict";
import test from "node:test";
import { tableInfo, tableToGeoJSON, withIds } from "../../wasmio/js/table.mjs";

// A table in @geom.Table's byte form (docs/FORMATS.md, "Table"), written by hand.
function tableBytes(): Uint8Array {
  const out: number[] = [];
  const u32 = (v: number) => out.push(v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >>> 24) & 255);
  const f64 = (v: number) => out.push(...new Uint8Array(new Float64Array([v]).buffer));
  const utf8 = (s: string) => { const b = new TextEncoder().encode(s); u32(b.length); out.push(...b); };
  // Features: a polygon with a hole, a two-point MultiPoint, one without geometry.
  [3, 3, 3, 9, 2].forEach(u32);
  out.push(5, 2, 0, 0);
  [1, 2, 2].forEach(u32); // part ends
  [2, 3, 3].forEach(u32); // ring ends
  [4, 7, 9].forEach(u32); // point ends
  [0, 0, 4, 0, 4, 4, 0, 0, 1, 1, 2, 1, 1, 1, 9, 9, 8, 8].forEach(f64);
  utf8("name");
  utf8("__proto__");
  // name: "a", absent, null; __proto__: 1, true, absent.
  out.push(4); utf8("a"); out.push(5, 0);
  out.push(3); f64(1); out.push(2, 5);
  return new Uint8Array(out);
}

test("tableToGeoJSON turns table bytes into features with their properties", () => {
  const fc = tableToGeoJSON(tableBytes());
  assert.equal(fc.type, "FeatureCollection");
  const [poly, points, empty] = fc.features;
  assert.deepEqual(poly.geometry, { type: "Polygon", coordinates: [[[0, 0], [4, 0], [4, 4], [0, 0]], [[1, 1], [2, 1], [1, 1]]] });
  assert.deepEqual(points.geometry, { type: "MultiPoint", coordinates: [[9, 9], [8, 8]] });
  assert.equal(empty.geometry, null);
  assert.equal(poly.properties.name, "a");
  assert.equal(Object.hasOwn(points.properties, "name"), false);
  assert.equal(empty.properties.name, null);
  // A `__proto__` key is an own property, not the object's prototype.
  assert.equal(Object.hasOwn(poly.properties, "__proto__"), true);
  assert.equal(Object.getPrototypeOf(poly.properties), Object.prototype);
  assert.equal(points.properties["__proto__"], true);
});

test("tableInfo reads the feature count and the keys alone", () => {
  assert.deepEqual(tableInfo(tableBytes()), { length: 3, columns: ["name", "__proto__"] });
  assert.deepEqual(tableInfo(tableBytes().buffer), { length: 3, columns: ["name", "__proto__"] });
});

test("withIds gives features the ids it is given, unless absent or null", () => {
  // A string, null, a number (docs/FORMATS.md "Property values").
  const ids = Uint8Array.of(4, 1, 0, 0, 0, 0x61, 0, 3, ...new Uint8Array(new Float64Array([7]).buffer));
  const fc = withIds(tableToGeoJSON(tableBytes()), ids);
  assert.deepEqual(fc.features.map((f) => f.id), ["a", undefined, 7]);
  assert.deepEqual(Object.keys(fc.features[0]), ["type", "id", "geometry", "properties"]);
  assert.equal("id" in fc.features[1], false);
});
