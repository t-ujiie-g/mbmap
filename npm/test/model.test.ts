import assert from "node:assert/strict";
import test from "node:test";
import { readGltf, splitGlb, textureTransform } from "../src/model/gltf.ts";
import { mercatorFrame, normalMatrix, placement, points, sphereFrame, triple, value } from "../src/model/place.ts";

const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64");
const uri = (...arrays: ArrayBufferView[]) =>
  `data:application/octet-stream;base64,${b64(Buffer.concat(arrays.map((a) => Buffer.from(a.buffer, a.byteOffset, a.byteLength))))}`;
const gltf = (json: object) => new TextEncoder().encode(JSON.stringify({ asset: { version: "2.0" }, ...json }));
const noLoad = async () => {
  throw new Error("nothing to load");
};

// A triangle: positions interleaved with a padding float (stride 16), u8 indices, and a sparse
// accessor that moves vertex 2.
const positions = new Float32Array([0, 0, 0, 9, 1, 0, 0, 9, 0, 1, 0, 9]);
const indices = new Uint8Array([0, 1, 2, 0]);
const sparseIndex = new Uint8Array([2, 0, 0, 0]);
const sparseValue = new Float32Array([5, 5, 5]);
const triangle = {
  buffers: [{ byteLength: 64, uri: uri(positions, indices, sparseIndex, sparseValue) }],
  bufferViews: [
    { buffer: 0, byteOffset: 0, byteLength: 48, byteStride: 16 },
    { buffer: 0, byteOffset: 48, byteLength: 3 },
    { buffer: 0, byteOffset: 52, byteLength: 1 },
    { buffer: 0, byteOffset: 56, byteLength: 12 },
  ],
  accessors: [
    { bufferView: 0, componentType: 5126, type: "VEC3", count: 3 },
    { bufferView: 1, componentType: 5121, type: "SCALAR", count: 3 },
    { bufferView: 0, componentType: 5126, type: "VEC3", count: 3, sparse: { count: 1, indices: { bufferView: 2, componentType: 5121 }, values: { bufferView: 3 } } },
  ],
  meshes: [{ primitives: [{ attributes: { POSITION: 0 }, indices: 1, material: 0 }, { attributes: { POSITION: 2 } }] }],
  materials: [{ pbrMetallicRoughness: { baseColorFactor: [1, 0, 0, 0.5] }, alphaMode: "BLEND", doubleSided: true }],
  nodes: [{ children: [1], translation: [10, 0, 0] }, { mesh: 0, scale: [2, 2, 2] }],
  scenes: [{ nodes: [0] }],
};

test("readGltf reads strided attributes, indices, sparse accessors, materials and world matrices", async () => {
  const m = await readGltf(gltf(triangle), noLoad);
  assert.equal(m.primitives.length, 2);
  const [a, b] = m.primitives;
  assert.deepEqual([...a.attributes.POSITION.data], [0, 0, 0, 1, 0, 0, 0, 1, 0]);
  assert.deepEqual({ size: a.attributes.POSITION.size, type: a.attributes.POSITION.type, normalized: a.attributes.POSITION.normalized }, { size: 3, type: 5126, normalized: false });
  assert.ok(a.indices instanceof Uint8Array);
  assert.deepEqual([...a.indices!], [0, 1, 2]);
  assert.deepEqual([...b.attributes.POSITION.data], [0, 0, 0, 1, 0, 0, 5, 5, 5]);
  assert.equal(b.material, -1);
  assert.deepEqual([...a.matrix], [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 10, 0, 0, 1]);
  assert.deepEqual(m.materials[0], { color: [1, 0, 0, 0.5], alphaMode: "BLEND", alphaCutoff: 0.5, doubleSided: true, unlit: false });
});

test("readGltf refuses what it cannot read safely", async () => {
  const refuse = async (json: object, message: RegExp) => assert.rejects(readGltf(gltf(json), noLoad), message);
  await refuse({ asset: { version: "1.0" } }, /only glTF 2\.0/);
  await refuse({ extensionsRequired: ["EXT_mesh_gpu_instancing"] }, /unsupported glTF extensions: EXT_mesh_gpu_instancing/);
  await refuse({ scenes: [{ nodes: [0] }], nodes: [{ children: [0] }] }, /node tree is malformed/);
  // A node with two parents: a DAG that doubles at each level.
  await refuse({ scenes: [{ nodes: [0] }], nodes: [{ children: [1, 2] }, { children: [3] }, { children: [3] }, {}] }, /node tree is malformed/);
  await refuse({ ...triangle, accessors: [{ ...triangle.accessors[0], count: 4 }, triangle.accessors[1], triangle.accessors[2]] }, /runs past its buffer view/);
  await refuse({ ...triangle, bufferViews: [{ buffer: 0, byteOffset: 60, byteLength: 48 }] }, /runs past its buffer/);
  // Names from Object.prototype are no types: "constructor" once made every size NaN and every check pass.
  await refuse({ ...triangle, accessors: [{ ...triangle.accessors[0], type: "constructor", count: 1e15 }, triangle.accessors[1], triangle.accessors[2]] }, /is not an attribute/);
  await refuse({ ...triangle, accessors: [{ ...triangle.accessors[0], componentType: "toString" }, triangle.accessors[1], triangle.accessors[2]] }, /is not an attribute/);
  const proto = await readGltf(gltf({ ...triangle, meshes: [{ primitives: [{ attributes: JSON.parse('{"POSITION": 0, "__proto__": 0}') }] }] }), noLoad);
  assert.equal(Object.getPrototypeOf(proto.primitives[0].attributes), null);
  const compressed = { ...triangle, bufferViews: [{ buffer: 0, byteLength: 48, extensions: { EXT_meshopt_compression: { buffer: 0, byteLength: 48, byteStride: 12, count: 3, mode: "ATTRIBUTES" } } }, ...triangle.bufferViews.slice(1)] };
  await refuse(compressed, /meshopt compression is not available/);
  await assert.rejects(readGltf(new TextEncoder().encode("{"), noLoad), SyntaxError);
});

test("readGltf hands meshopt views to the decoder and loads external buffers through `load`", async () => {
  const calls: unknown[] = [];
  const json = {
    ...triangle,
    buffers: [{ byteLength: 64, uri: "triangle.bin" }],
    bufferViews: [{ buffer: 0, byteLength: 48, byteStride: 16, extensions: { KHR_meshopt_compression: { buffer: 0, byteOffset: 4, byteLength: 8, byteStride: 16, count: 3, mode: "ATTRIBUTES", filter: "NONE" } } }, ...triangle.bufferViews.slice(1)],
  };
  const bytes = new Uint8Array(Buffer.from(uri(positions, indices, sparseIndex, sparseValue).split(",")[1], "base64"));
  const m = await readGltf(gltf(json), async (u) => (u === "triangle.bin" ? bytes : noLoad()), (target, count, size, source, mode, filter) => {
    calls.push([count, size, source.length, mode, filter]);
    target.set(new Uint8Array(positions.buffer));
  });
  assert.deepEqual(calls, [[3, 16, 8, "ATTRIBUTES", "NONE"]]);
  assert.deepEqual([...m.primitives[0].attributes.POSITION.data], [0, 0, 0, 1, 0, 0, 0, 1, 0]);
});

test("splitGlb reads a GLB's JSON and binary chunks", () => {
  const json = new TextEncoder().encode('{"asset":{"version":"2.0"}} ');
  const bin = new Uint8Array([1, 2, 3, 4]);
  const glb = new Uint8Array(12 + 8 + json.length + 8 + bin.length);
  const v = new DataView(glb.buffer);
  v.setUint32(0, 0x46546c67, true);
  v.setUint32(4, 2, true);
  v.setUint32(8, glb.length, true);
  v.setUint32(12, json.length, true);
  v.setUint32(16, 0x4e4f534a, true);
  glb.set(json, 20);
  v.setUint32(20 + json.length, bin.length, true);
  v.setUint32(24 + json.length, 0x004e4942, true);
  glb.set(bin, 28 + json.length);
  const out = splitGlb(glb);
  assert.deepEqual(out.json, { asset: { version: "2.0" } });
  assert.deepEqual([...out.bin!], [1, 2, 3, 4]);
  v.setUint32(12, 1 << 30, true);
  assert.throws(() => splitGlb(glb), /runs past the file/);
});

test("textureTransform is KHR_texture_transform's translation x rotation x scale", () => {
  const m = textureTransform({ offset: [0.5, 0.25], rotation: Math.PI / 2, scale: [2, 3] });
  const apply = (u: number, v: number) => [m[0] * u + m[3] * v + m[6], m[1] * u + m[4] * v + m[7]].map((x) => Math.round(x * 1e12) / 1e12);
  assert.deepEqual(apply(1, 0), [0.5, 2.25]);
  assert.deepEqual(apply(0, 1), [-2.5, 0.25]);
});

test("placement turns z clockwise seen from above, after scaling and before translating", () => {
  const m = placement([2, 1, 1], [0, 0, 90], [10, 20, 30]);
  const east = [m[0] + m[12], m[1] + m[13], m[2] + m[14]].map((x) => Math.round(x * 1e9) / 1e9);
  // The model's east, 2 m once scaled, turned clockwise to the south.
  assert.deepEqual(east, [10, 18, 30]);
});

test("mercatorFrame and sphereFrame take east, north, up meters to Mercator and the unit sphere", () => {
  const f = mercatorFrame(0, 0, 100);
  const k = 1 / (2 * Math.PI * 6378137);
  assert.deepEqual([...f], [k, 0, 0, 0, 0, -k, 0, 0, 0, 0, k, 0, 0.5, 0.5, 100 * k, 1]);
  const s = sphereFrame(90, 0, 0);
  // At 90° E on the equator: east is -z, north +y, up +x.
  const round = (a: ArrayLike<number>) => [...a].map((x) => Math.round(x * 6371008.8 * 1e9) / 1e9 + 0);
  assert.deepEqual(round(s.subarray(0, 3)), [0, 0, -1]);
  assert.deepEqual(round(s.subarray(4, 7)), [0, 1, 0]);
  assert.deepEqual(round(s.subarray(8, 11)), [1, 0, 0]);
  assert.deepEqual([...s.subarray(12, 15)].map((x) => Math.round(x * 1e12) / 1e12), [1, 0, 0]);
});

test("points reads Points, MultiPoints, Features and collections; value reads ['get', key]", () => {
  const data = {
    type: "FeatureCollection",
    features: [
      { type: "Feature", properties: { h: 3 }, geometry: { type: "Point", coordinates: [1, 2, 7] } },
      { type: "Feature", properties: null, geometry: { type: "MultiPoint", coordinates: [[3, 4], [5, "x"]] } },
      { type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: [[0, 0], [1, 1]] } },
    ],
  };
  const p = points(data);
  assert.deepEqual(p.map((x) => x.coords), [[1, 2, 7], [3, 4]]);
  assert.equal(value(["get", "h"], p[0].props, 1), 3);
  assert.equal(value(["get", "h"], p[1].props, 1), 1);
  assert.equal(value(5, {}, 1), 5);
  assert.deepEqual(points({ type: "Point", coordinates: [9, 9] }).map((x) => x.coords), [[9, 9]]);
});

test("triple reads three numbers, as a whole or each by ['get', key], else its fallback", () => {
  const props = { turn: 45, size: [2, 3, 4], bad: "x" };
  assert.deepEqual(triple([0, 0, ["get", "turn"]], props, [9, 9, 9]), [0, 0, 45]);
  assert.deepEqual(triple(["get", "size"], props, [1, 1, 1]), [2, 3, 4]);
  assert.deepEqual(triple([0, ["get", "bad"], 0], props, [1, 1, 1]), [1, 1, 1]);
  assert.deepEqual(triple([1, 2], props, [1, 1, 1]), [1, 1, 1]);
  assert.deepEqual(triple(undefined, props, [1, 1, 1]), [1, 1, 1]);
});

test("normalMatrix is the inverse transpose of the upper 3x3; points skips MultiPoint members that are not positions", () => {
  // Scale 2, 4, 8: normals scale by 1/2, 1/4, 1/8.
  assert.deepEqual(Array.from(normalMatrix([2, 0, 0, 0, 0, 4, 0, 0, 0, 0, 8, 0, 5, 6, 7, 1])), [0.5, 0, 0, 0, 0.25, 0, 0, 0, 0.125]);
  const p = points({ type: "MultiPoint", coordinates: [null, [1, 2], 3, [4, 5, 6]] });
  assert.deepEqual(p.map((x) => x.coords), [[1, 2], [4, 5, 6]]);
});
