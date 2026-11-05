import assert from "node:assert/strict";
import test from "node:test";
import { headerCrs, headerLength, levelBounds, readHeader, search, selectBytes, selectUrl, treeBytes } from "./fgb.mjs";

// flatgeobuf 4.6.1's `geojson.serialize` of a point and a triangle, without an index.
const TWO = Uint8Array.from(Buffer.from("6667620366676200940000001c00000018001c000400000000000000000000000000080010000e0018000000180000001c00000000000000020000000000000000000000020000004c310000030000003c0000001c00000004000000d8ffffff00000002040000000100000062000000ecffffff0000000b04000000010000007300000008000c0008000700080000000000000a04000000010000006e0000006c0000000c00000008000e0008000400080000004000000018000000000012000c0000000800000000000000000007001200000000000001040000000200000000000000007061400000000000a0414000000000160000000000000000000000f83f010003000000e381820200010000940000000c00000008000e0008000400080000006c00000018000000000012000c000000080000000000000000000700120000000000000304000000080000000000000000000000000000000000000000000000000000400000000000000000000000000000004000000000000000400000000000000000000000000000000013000000000000000000000000c001000000000002000000", "hex"));

// A packed R-tree of `nodes` ([minX, minY, maxX, maxY, ref] each, root first).
function tree(nodes) {
  const b = new Uint8Array(nodes.length * 40);
  const v = new DataView(b.buffer);
  nodes.forEach((n, i) => {
    for (let k = 0; k < 4; k++) v.setFloat64(i * 40 + k * 8, n[k], true);
    v.setBigUint64(i * 40 + 32, BigInt(n[4]), true);
  });
  return async (offset, length) => b.subarray(offset, offset + length);
}

// Three items under two nodes of two children.
const THREE = [[0, 0, 11, 11, 1], [0, 0, 6, 6, 3], [10, 10, 11, 11, 5], [0, 0, 1, 1, 0], [5, 5, 6, 6, 100], [10, 10, 11, 11, 250]];

test("levelBounds and treeBytes lay the tree out as flatgeobuf does", () => {
  assert.deepEqual(levelBounds(3, 2), [[3, 6], [1, 3], [0, 1]]);
  assert.deepEqual(levelBounds(1, 16), [[1, 2], [0, 1]]);
  assert.equal(treeBytes(17, 16), 20 * 40);
  assert.equal(treeBytes(10, 1), (10 + 5 + 3 + 2 + 1) * 40);
});

test("search finds the features whose boxes meet the rectangle, with their lengths", async () => {
  assert.deepEqual(await search(3, 2, [0, 0, 5.5, 5.5], tree(THREE)), [[0, 0, 100], [100, 1, 150]]);
  assert.deepEqual(await search(3, 2, [10, 10, 12, 12], tree(THREE)), [[250, 2, null]]);
  assert.deepEqual(await search(3, 2, [20, 20, 30, 30], tree(THREE)), []);
});

test("search refuses an index that does not form a tree", async () => {
  const loop = THREE.map((n, i) => (i === 0 ? [0, 0, 11, 11, 0] : n));
  await assert.rejects(search(3, 2, [0, 0, 1, 1], tree(loop)), /a node at the wrong level/);
  const far = THREE.map((n, i) => (i === 0 ? [0, 0, 11, 11, 99] : n));
  await assert.rejects(search(3, 2, [0, 0, 1, 1], tree(far)), /past the end of the index/);
  await assert.rejects(search(3, 2, [0, 0, 1, 1], async () => new Uint8Array(8)), /index past the end/);
});

test("readHeader reads the count, node size and CRS", () => {
  assert.equal(headerLength(TWO), 0x94);
  assert.deepEqual(readHeader(TWO), { length: 0x94, count: 2, nodeSize: 0, crs: null });
  assert.throws(() => readHeader(TWO.subarray(0, 40)), /header past the end/);
  assert.throws(() => headerLength(new Uint8Array(12)), /not a FlatGeobuf file/);
  const big = TWO.slice();
  new DataView(big.buffer).setUint32(8, 11 * 1024 * 1024, true);
  assert.throws(() => headerLength(big), /invalid header size/);
});

test("headerCrs takes an EPSG code, else the WKT", () => {
  assert.equal(headerCrs(null), undefined);
  assert.equal(headerCrs({ org: "EPSG", code: 6677, wkt: null }), 6677);
  assert.equal(headerCrs({ org: null, code: 4326, wkt: null }), 4326);
  assert.deepEqual(headerCrs({ org: "ESRI", code: 102100, wkt: "PROJCS[]" }), { wkt: "PROJCS[]" });
  assert.equal(headerCrs({ org: "ESRI", code: 102100, wkt: " " }), undefined);
});

test("a bbox needs an index and a valid rectangle", async () => {
  await assert.rejects(selectBytes(TWO, [0, 0, 1, 1]), /has no index/);
  for (const bbox of [[0, 0, 1], [1, 0, 0, 1], [0, 0, NaN, 1], "0,0,1,1"]) {
    await assert.rejects(selectUrl("http://127.0.0.1:1/x.fgb", undefined, bbox, 1000, {}), /invalid bbox/);
  }
});
