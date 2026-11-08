import assert from "node:assert/strict";
import test from "node:test";
import type { DracoMesh } from "../src/model/gltf.ts";
import {
  cartesian, checkSpatialReference, dracoMetadata, geometryBufferOf, materialOf, nodeCenter, nodeResources, readI3sAttribute, readI3sGeometry, textureOf,
  type I3sLayer, type I3sNode,
} from "../src/i3s/content.ts";
import { eastNorthUp } from "../src/tiles/geo.ts";

const CENTER = [139.7671, 35.6812, 10];
const PLAIN = { offset: 8, position: { type: "Float32", component: 3 }, normal: { type: "Float32", component: 3 }, uv0: { type: "Float32", component: 2 }, color: { type: "UInt8", component: 4 }, featureId: { type: "UInt64", component: 1 }, faceRange: { type: "UInt32", component: 2 } };
const DRACO = { compressedAttributes: { encoding: "draco", attributes: ["position", "feature-index"] } };
const layer: I3sLayer = {
  spatialReference: { wkid: 4326 },
  store: { normalReferenceFrame: "earth-centered" },
  geometryDefinitions: [{ geometryBuffers: [PLAIN, DRACO] }, { geometryBuffers: [PLAIN] }],
  materialDefinitions: [
    { pbrMetallicRoughness: { baseColorFactor: [1, 0.5, 0.25, 1] }, alphaMode: "blend", cullFace: "none" },
    { pbrMetallicRoughness: { baseColorTexture: { textureSetDefinitionId: 0 } } },
  ],
  textureSetDefinitions: [{ atlas: true, formats: [{ name: "0_0_1", format: "dds" }, { name: "0", format: "jpg" }] }, { formats: [{ name: "1", format: "ktx2" }] }],
  attributeStorageInfo: [
    { key: "f_0", name: "OBJECTID", ordering: ["attributeValues"], attributeValues: { valueType: "Oid32" } },
    { key: "f_1", name: "NAME", header: [{ property: "count", valueType: "UInt32" }, { property: "attributeValuesByteCount", valueType: "UInt32" }], ordering: ["attributeByteCounts", "attributeValues"], attributeByteCounts: { valueType: "UInt32" }, attributeValues: { valueType: "String" } },
  ],
};
const node: I3sNode = { obb: { center: CENTER }, mesh: { geometry: { definition: 0, resource: 7 }, material: { definition: 1, resource: 7 }, attribute: { resource: 7 } } };

const bytesOf = (...arrays: ArrayBufferView[]) => {
  const out = new Uint8Array(arrays.reduce((a, x) => a + x.byteLength, 0));
  let at = 0;
  for (const a of arrays) {
    out.set(new Uint8Array(a.buffer, a.byteOffset, a.byteLength), at);
    at += a.byteLength;
  }
  return out;
};

/** Two triangles: the center, 10 m up, a hundred-thousandth of a degree east; then the same shifted north. */
function plain(ids = [5, 0, 6, 0], ranges = [0, 0, 1, 1], vertexCount = 6, featureCount = 2) {
  const d = 1e-5;
  const pos = new Float32Array([0, 0, 0, 0, 0, 10, d, 0, 0, 0, d, 0, 0, d, 10, d, d, 0]);
  const up = cartesian(CENTER[0], CENTER[1], CENTER[2]);
  const len = Math.hypot(up[0], up[1], up[2] / (1 - 1 / 298.257223563) ** 2);
  const normal = [up[0] / len, up[1] / len, up[2] / (1 - 1 / 298.257223563) ** 2 / len];
  const normals = new Float32Array(Array.from({ length: 6 }, () => normal).flat());
  const uv = new Float32Array([0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0]);
  const color = new Uint8Array(Array.from({ length: 6 }, (_, i) => [i, 10, 20, 255]).flat());
  return bytesOf(new Uint32Array([vertexCount, featureCount]), pos, normals, uv, color, new Uint32Array(ids), new Uint32Array(ranges));
}

test("readI3sGeometry places an uncompressed buffer in east, north, up meters around the node's center", () => {
  const g = readI3sGeometry(plain(), layer, node, 0);
  assert.deepEqual(g.center, CENTER);
  assert.equal(g.count, 6);
  const p = g.primitive.attributes.POSITION.data;
  assert.deepEqual(Array.from(p.subarray(0, 3)), [0, 0, 0]);
  assert.ok(Math.abs(p[5] - 10) < 1e-5 && Math.abs(p[3]) < 1e-5 && Math.abs(p[4]) < 1e-5);
  // 1e-5 degrees of longitude at 35.68 degrees is about 0.905 m east, 1e-5 of latitude about 1.109 m north.
  assert.ok(Math.abs(p[6] - 0.9046) < 1e-3 && Math.abs(p[7]) < 1e-3);
  assert.ok(Math.abs(p[10] - 1.1094) < 1e-3 && Math.abs(p[9]) < 1e-3);
  const n = g.primitive.attributes.NORMAL.data;
  assert.ok(Math.abs(n[0]) < 1e-6 && Math.abs(n[1]) < 1e-6 && Math.abs(n[2] - 1) < 1e-6);
  assert.deepEqual(Array.from(g.primitive.attributes.TEXCOORD_0.data.subarray(0, 4)), [0, 0, 0, 1]);
  assert.deepEqual(g.primitive.attributes.COLOR_0, { data: new Uint8Array(Array.from({ length: 6 }, (_, i) => [i, 10, 20, 255]).flat()), size: 4, type: 5121, normalized: true });
  assert.deepEqual(Array.from(g.primitive.attributes._BATCHID.data), [0, 0, 0, 1, 1, 1]);
  assert.deepEqual(Array.from(g.featureIds), [5, 6]);
  assert.equal(g.primitive.indices, undefined);
  assert.equal(g.primitive.material, 0);
  assert.equal(g.primitive.mode, 4);
});

test("readI3sGeometry keeps east-north-up normals and gives ids past 2^53 as strings", () => {
  const enu = { ...layer, store: { normalReferenceFrame: "east-north-up" } };
  const g = readI3sGeometry(plain([1, 0, 0xffffffff, 0x200000]), enu, node, 0);
  assert.deepEqual(g.featureIds, ["1", String(0x200000n * 2n ** 32n + 0xffffffffn)]);
  const raw = plain().slice(8 + 72, 8 + 72 + 72);
  assert.deepEqual(new Uint8Array(g.primitive.attributes.NORMAL.data.buffer), raw);
});

test("readI3sGeometry reads the counts from the node page when the buffer has no header", () => {
  const noHeader = { ...layer, geometryDefinitions: [{ geometryBuffers: [{ ...PLAIN, offset: 0 }] }] };
  const n = { ...node, mesh: { geometry: { definition: 0, resource: 7, vertexCount: 6, featureCount: 2 } } };
  assert.equal(readI3sGeometry(plain().subarray(8), noHeader, n, 0).count, 6);
});

test("readI3sGeometry refuses malformed uncompressed buffers", () => {
  assert.throws(() => readI3sGeometry(plain().subarray(0, 4), layer, node, 0), /shorter than its header/);
  assert.throws(() => readI3sGeometry(plain([5, 0, 6, 0], [0, 0, 1, 1], 9), layer, node, 0), /runs past/);
  assert.throws(() => readI3sGeometry(plain([5, 0, 6, 0], [0, 0, 1, 1], 5), layer, node, 0), /vertex count/);
  assert.throws(() => readI3sGeometry(plain([5, 0, 6, 0], [0, 0, 1, 1], 6, 0xffffffff), layer, node, 0), /feature count/);
  assert.throws(() => readI3sGeometry(plain([5, 0, 6, 0], [0, 0, 1, 2]), layer, node, 0), /face range/);
  assert.throws(() => readI3sGeometry(plain([5, 0, 6, 0], [1, 0, 1, 1]), layer, node, 0), /face range/);
  assert.throws(() => readI3sGeometry(plain().subarray(0, plain().length - 1), layer, node, 0), /faceRange runs past/);
  assert.throws(() => readI3sGeometry(plain(), layer, node, 3), /not defined/);
  assert.throws(() => readI3sGeometry(plain(), { ...layer, spatialReference: { wkid: 3857 } }, node, 0), /3857 is not supported/);
  const odd = { ...layer, geometryDefinitions: [{ geometryBuffers: [{ ...PLAIN, position: { type: "Float64", component: 3 } }] }] };
  assert.throws(() => readI3sGeometry(plain(), odd, node, 0), /position as Float64/);
  const lzma = { ...layer, geometryDefinitions: [{ geometryBuffers: [{ compressedAttributes: { encoding: "lzma" } }] }] };
  assert.throws(() => readI3sGeometry(plain(), lzma, node, 0), /lzma geometry/);
  assert.throws(() => readI3sGeometry(plain(), layer, { ...node, obb: undefined }, 0), /no center/);
});

const varint = (n: number) => {
  const out = [];
  do {
    out.push((n & 0x7f) | (n > 0x7f ? 0x80 : 0));
    n >>>= 7;
  } while (n > 0);
  return out;
};
const text = (s: string) => [s.length, ...new TextEncoder().encode(s)];
const entry = (name: string, value: Uint8Array) => [...text(name), ...varint(value.length), ...value];
const f64 = (x: number) => new Uint8Array(new Float64Array([x]).buffer);

/** A Draco header with metadata: position (id 0) scaled 2 in x, a sub-metadata to skip; feature indices (id 3) with ids 7 and 9. */
function dracoBytes(withMetadata = true) {
  const position = [...varint(1), ...entry("i3s-scale_x", f64(2)), ...varint(1), ...text("sub"), ...varint(1), ...entry("k", new Uint8Array([1])), ...varint(0)];
  const ids = [...varint(2), ...entry("i3s-attribute-type", new TextEncoder().encode("feature-index")), ...entry("i3s-feature-ids", new Uint8Array(new Int32Array([7, 9]).buffer)), ...varint(0)];
  const meta = [...varint(2), ...varint(0), ...position, ...varint(3), ...ids, ...varint(0), ...varint(0)];
  return new Uint8Array([68, 82, 65, 67, 79, 2, 2, 1, 1, 0, withMetadata ? 0x80 : 0, ...meta]);
}

const fakeDraco = (indices: number[], featureIndex: number[]) => (): DracoMesh => ({
  indices: new Uint32Array(indices),
  attributes: new Map([
    [0, { data: new Float32Array([0, 0, 0, 0, 0, 10, 1e-5, 0, 0]), size: 3, type: 5126, normalized: false, dracoType: 0 }],
    [3, { data: new Uint32Array(featureIndex), size: 1, type: 5125, normalized: false, dracoType: 4 }],
  ]),
});

test("dracoMetadata reads each attribute's top-level entries and skips sub-metadata", () => {
  const m = dracoMetadata(dracoBytes());
  assert.deepEqual([...m.keys()], [0, 3]);
  assert.deepEqual([...m.get(0)!.keys()], ["i3s-scale_x"]);
  assert.equal(new TextDecoder().decode(m.get(3)!.get("i3s-attribute-type")), "feature-index");
  assert.equal(dracoMetadata(dracoBytes(false)).size, 0);
  assert.equal(dracoMetadata(new Uint8Array([1, 2, 3])).size, 0);
  assert.deepEqual([...dracoMetadata(dracoBytes().subarray(0, 48)).keys()], [0]);
});

test("readI3sGeometry reads a Draco buffer named by attribute types and metadata, scales and feature ids applied", () => {
  const g = readI3sGeometry(dracoBytes(), layer, node, 1, fakeDraco([0, 1, 2], [1, 1, 0]));
  const p = g.primitive.attributes.POSITION.data;
  assert.ok(Math.abs(p[6] - 2 * 0.9046) < 2e-3);
  assert.deepEqual(Array.from(g.primitive.indices!), [0, 1, 2]);
  assert.deepEqual(Array.from(g.primitive.attributes._BATCHID.data), [1, 1, 0]);
  assert.deepEqual(Array.from(g.featureIds), [7, 9]);
  assert.throws(() => readI3sGeometry(dracoBytes(), layer, node, 1, fakeDraco([0, 1, 3], [0, 0, 0])), /index is past/);
  assert.throws(() => readI3sGeometry(dracoBytes(), layer, node, 1, fakeDraco([0, 1, 2], [0, 2, 0])), /past the feature ids/);
  assert.throws(() => readI3sGeometry(dracoBytes(), layer, node, 1), /no Draco decoder/);
  const noPosition = (): DracoMesh => ({ indices: new Uint32Array(0), attributes: new Map() });
  assert.throws(() => readI3sGeometry(dracoBytes(), layer, node, 1, noPosition), /no float positions/);
});

test("checkSpatialReference and nodeCenter", () => {
  assert.doesNotThrow(() => checkSpatialReference({ spatialReference: { wkid: 102100, latestWkid: 4326 } }));
  assert.throws(() => checkSpatialReference({}), /none is not supported/);
  assert.deepEqual(nodeCenter({ mbs: [1, 2, 3, 4] }), [1, 2, 3]);
});

test("geometryBufferOf prefers Draco; textureOf takes JPEG or PNG only; nodeResources names the REST paths", () => {
  assert.deepEqual(geometryBufferOf(layer, 0), { index: 1, draco: true });
  assert.deepEqual(geometryBufferOf(layer, 1), { index: 0, draco: false });
  assert.equal(geometryBufferOf(layer, 2), undefined);
  assert.deepEqual(textureOf(layer, 1), { name: "0", format: "jpg", atlas: true });
  assert.equal(textureOf(layer, 0), undefined);
  const ktx = { ...layer, materialDefinitions: [{ pbrMetallicRoughness: { baseColorTexture: { textureSetDefinitionId: 1 } } }] };
  assert.equal(textureOf(ktx, 0), undefined);
  assert.deepEqual(nodeResources(layer, node), { geometry: "nodes/7/geometries/1", buffer: 1, texture: "nodes/7/textures/0", attributes: ["nodes/7/attributes/f_0/0", "nodes/7/attributes/f_1/0"] });
  assert.equal(nodeResources(layer, {}), undefined);
});

test("materialOf maps I3S material definitions", () => {
  assert.deepEqual(materialOf(layer, 0, false), { color: [1, 0.5, 0.25, 1], texture: undefined, alphaMode: "BLEND", alphaCutoff: 0.25, doubleSided: true, unlit: false });
  const m = materialOf(layer, 1, true);
  assert.deepEqual(m.texture, { image: 0, wrapS: 10497, wrapT: 10497, minFilter: 9987, magFilter: 9729, texCoord: 0 });
  assert.deepEqual([m.color, m.alphaMode, m.doubleSided], [[1, 1, 1, 1], "OPAQUE", false]);
  assert.equal(materialOf(layer, undefined, false).alphaMode, "OPAQUE");
});

test("readI3sAttribute reads object ids, strings, aligned doubles and 64-bit values", () => {
  assert.deepEqual(readI3sAttribute(bytesOf(new Uint32Array([2, 11, 12])), layer.attributeStorageInfo![0]), new Uint32Array([11, 12]));
  const names = [new TextEncoder().encode("Tōkyō\0"), new TextEncoder().encode("B\0")];
  const strings = bytesOf(new Uint32Array([2, names[0].length + names[1].length, names[0].length, names[1].length]), ...names);
  assert.deepEqual(readI3sAttribute(strings, layer.attributeStorageInfo![1]), ["Tōkyō", "B"]);
  const height = { key: "f_2", name: "h", ordering: ["attributeValues"], attributeValues: { valueType: "Float64" } };
  assert.deepEqual(readI3sAttribute(bytesOf(new Uint32Array([2, 0]), new Float64Array([1.5, -2])), height), new Float64Array([1.5, -2]));
  const big = { ...height, attributeValues: { valueType: "UInt64" } };
  assert.deepEqual(readI3sAttribute(bytesOf(new Uint32Array([1, 0]), new BigUint64Array([2n ** 60n])), big), new BigUint64Array([2n ** 60n]));
  const oids = { key: "f_3", name: "ids", objectIds: { valueType: "Oid32" } };
  assert.deepEqual(readI3sAttribute(bytesOf(new Uint32Array([1, 4])), oids), new Uint32Array([4]));
});

test("readI3sAttribute refuses malformed buffers", () => {
  const info = layer.attributeStorageInfo![1];
  assert.throws(() => readI3sAttribute(new Uint8Array(2), info), /bad header/);
  assert.throws(() => readI3sAttribute(bytesOf(new Uint32Array([1 << 30, 0])), info), /bad count/);
  assert.throws(() => readI3sAttribute(bytesOf(new Uint32Array([2, 0, 1])), info), /values run past/);
  assert.throws(() => readI3sAttribute(bytesOf(new Uint32Array([1, 9, 9])), info), /strings run past/);
  assert.throws(() => readI3sAttribute(bytesOf(new Uint32Array([1, 1])), { key: "k", name: "s", ordering: ["attributeValues"], attributeValues: { valueType: "String" } }), /without byte counts/);
  assert.throws(() => readI3sAttribute(bytesOf(new Uint32Array([1, 1])), { key: "k", name: "x", ordering: ["attributeValues"], attributeValues: { valueType: "Int128" } }), /unknown type/);
  assert.throws(() => readI3sAttribute(bytesOf(new Uint32Array([1, 1])), { key: "k", name: "x", ordering: ["attributeValues"], attributeValues: { valueType: "Int32", valuesPerElement: 2 } }), /2 values per element/);
  assert.throws(() => readI3sAttribute(bytesOf(new Uint32Array([1, 1])), { key: "k", name: "x", ordering: ["other"] }), /no other/);
});

test("cartesian agrees with the east-north-up frame's origin", () => {
  const p = cartesian(0, 0, 0);
  assert.deepEqual(p, [6378137, 0, 0]);
  assert.deepEqual(Array.from(eastNorthUp(p).subarray(8, 11)), [1, 0, 0]);
});
