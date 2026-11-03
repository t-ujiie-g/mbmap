import assert from "node:assert/strict";
import test from "node:test";
import { readClusterFeatures } from "./features.mjs";

const encoder = new TextEncoder();

/** Cluster features as the wasm writes them: count, then x, y, id value, and keyed values. */
function encode(features) {
  const parts = [];
  const u32 = (n) => parts.push(new Uint8Array(new Uint32Array([n]).buffer));
  const f64 = (x) => parts.push(new Uint8Array(new Float64Array([x]).buffer));
  const string = (s) => {
    const b = encoder.encode(s);
    u32(b.length);
    parts.push(b);
  };
  const value = (v) => {
    if (v === null) parts.push(new Uint8Array([0]));
    else if (typeof v === "boolean") parts.push(new Uint8Array([v ? 2 : 1]));
    else if (typeof v === "number") (parts.push(new Uint8Array([3])), f64(v));
    else if (typeof v === "string") (parts.push(new Uint8Array([4])), string(v));
    else parts.push(new Uint8Array([5]));
  };
  u32(features.length);
  for (const f of features) {
    f64(f.x);
    f64(f.y);
    value(f.id);
    u32(f.props.length);
    for (const [k, v] of f.props) {
      string(k);
      value(v);
    }
  }
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) (out.set(p, at), (at += p.length));
  return out;
}

test("readClusterFeatures gives GeoJSON points with ids and every kind of value", () => {
  const bytes = encode([
    { x: 139.5, y: 35.25, id: 7, props: [["cluster", true], ["point_count", 12], ["name", "駅"], ["none", null], ["no", false]] },
    { x: -1, y: 2, id: undefined, props: [] },
  ]);
  const [a, b] = readClusterFeatures(bytes);
  assert.deepEqual(a.geometry, { type: "Point", coordinates: [139.5, 35.25] });
  assert.equal(a.id, 7);
  assert.deepEqual({ ...a.properties }, { cluster: true, point_count: 12, name: "駅", none: null, no: false });
  assert.equal("id" in b, false);
  assert.deepEqual(b.geometry.coordinates, [-1, 2]);
  assert.deepEqual({ ...b.properties }, {});
});

test("readClusterFeatures keeps a __proto__ key as a plain property", () => {
  const [f] = readClusterFeatures(encode([{ x: 0, y: 0, id: "a", props: [["__proto__", "x"], ["constructor", 1]] }]));
  assert.equal(Object.getPrototypeOf(f.properties), null);
  assert.equal(f.properties.__proto__, "x");
  assert.equal(f.properties.constructor, 1);
  assert.equal({}.polluted, undefined);
  assert.equal(f.id, "a");
});

test("readClusterFeatures reads an offset view and no features", () => {
  const inner = encode([{ x: 1, y: 2, id: 3, props: [] }]);
  const padded = new Uint8Array(inner.length + 5);
  padded.set(inner, 5);
  assert.equal(readClusterFeatures(padded.subarray(5)).length, 1);
  assert.deepEqual(readClusterFeatures(encode([])), []);
});
