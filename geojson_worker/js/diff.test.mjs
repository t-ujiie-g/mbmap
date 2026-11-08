import assert from "node:assert/strict";
import test from "node:test";
import { encodeDiff, loadInput } from "./diff.mjs";

const decoder = new TextDecoder();

/** Reads the bytes back: the FeatureCollection, and a reader over the rest. */
function decode(bytes) {
  const n = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, true);
  const collection = JSON.parse(decoder.decode(bytes.subarray(4, 4 + n)));
  const rest = bytes.subarray(4 + n);
  const r = new DataView(rest.buffer, rest.byteOffset, rest.byteLength);
  let at = 0;
  const u8 = () => r.getUint8(at++);
  const u32 = () => ((at += 4), r.getUint32(at - 4, true));
  const utf8 = () => {
    const n = u32();
    at += n;
    return decoder.decode(rest.subarray(at - n, at));
  };
  const value = () => {
    const tag = u8();
    if (tag === 3) return ((at += 8), r.getFloat64(at - 8, true));
    if (tag === 4) return utf8();
    return [null, false, true, , , undefined][tag];
  };
  return { collection, u8, u32, utf8, value, end: () => at === rest.length };
}

test("encodeDiff puts added features and new geometries in one FeatureCollection", () => {
  const point = { type: "Point", coordinates: [1, 2] };
  const d = decode(encodeDiff({
    add: [{ type: "Feature", id: 3, geometry: point, properties: { a: 1 }, extra: true }, { id: "x", geometry: 5, properties: "no" }],
    update: [{ id: 3, newGeometry: point }, { id: 4, addOrUpdateProperties: [{ key: "a", value: 2 }] }, { id: 5, newGeometry: 1 }],
  }));
  assert.deepEqual(d.collection, {
    type: "FeatureCollection",
    features: [
      { type: "Feature", id: 3, geometry: point, properties: { a: 1 } },
      { type: "Feature", id: "x", geometry: null, properties: null },
      { type: "Feature", geometry: point, properties: null },
      { type: "Feature", geometry: null, properties: null },
    ],
  });
  assert.equal(d.u8(), 0);
  assert.equal(d.u32(), 0);
  assert.equal(d.u32(), 2);
  assert.equal(d.u32(), 3);
  assert.deepEqual([d.value(), d.u8(), d.u32(), d.u32()], [3, 1, 0, 0]);
  assert.deepEqual([d.value(), d.u8(), d.u32(), d.u32(), d.utf8(), d.value()], [4, 0, 0, 1, "a", 2]);
  assert.deepEqual([d.value(), d.u8(), d.u32(), d.u32()], [5, 1, 0, 0]);
  assert.equal(d.end(), true);
});

test("encodeDiff writes removals, property edits and every kind of value", () => {
  const d = decode(encodeDiff({
    removeAll: true,
    remove: [1, "1", null, { a: 1 }, true],
    update: [
      { id: "k", removeAllProperties: true, removeProperties: ["p", "q"], addOrUpdateProperties: [{ key: "o", value: { b: [1] } }, { key: "u" }] },
      { addOrUpdateProperties: [{ key: "n", value: null }, { key: "f", value: false }] },
      { id: { x: 1 }, removeAllProperties: true },
    ],
  }));
  assert.deepEqual(d.collection.features, []);
  assert.equal(d.u8(), 1);
  assert.equal(d.u32(), 4);
  assert.deepEqual([d.value(), d.value(), d.value(), d.value()], [1, "1", null, true]);
  assert.equal(d.u32(), 0);
  assert.equal(d.u32(), 2);
  assert.deepEqual([d.value(), d.u8(), d.u32(), d.utf8(), d.utf8()], ["k", 2, 2, "p", "q"]);
  assert.deepEqual([d.u32(), d.utf8(), d.value(), d.utf8(), d.value()], [2, "o", '{"b":[1]}', "u", undefined]);
  assert.deepEqual([d.value(), d.u8(), d.u32(), d.u32()], [undefined, 0, 0, 2]);
  assert.deepEqual([d.utf8(), d.value(), d.utf8(), d.value()], ["n", null, "f", false]);
  assert.equal(d.end(), true);
});

test("loadInput puts the promoteId before the data", () => {
  const data = new Uint8Array([123, 125]);
  const [head, rest] = loadInput("名前", data);
  assert.equal(new DataView(head.buffer).getUint32(0, true), 6);
  assert.equal(decoder.decode(head.subarray(4)), "名前");
  assert.equal(rest, data);
  assert.deepEqual([...loadInput(undefined, data)[0]], [0, 0, 0, 0]);
});
