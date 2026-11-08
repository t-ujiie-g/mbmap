import assert from "node:assert/strict";
import test from "node:test";
import { readGltf, type StructuralMetadata } from "../src/model/gltf.ts";
import { batchTableProperties, featureId, MAX_FEATURES, propertyTableProperties } from "../src/tiles/properties.ts";

const bytes = (...arrays: ArrayBufferView[]) => new Uint8Array(Buffer.concat(arrays.map((a) => Buffer.from(a.buffer, a.byteOffset, a.byteLength))));
const plain = (r: Record<string, unknown>) => JSON.parse(JSON.stringify(r, (_, v) => (typeof v === "bigint" ? `${v}n` : v)));

test("batchTableProperties reads JSON arrays and binary references by batch ID", () => {
  const binary = bytes(new Float64Array([1.5, 2.5]), new Int8Array([-1, 2, 3, -4]));
  const json = {
    name: ["a", "b"],
    height: { byteOffset: 0, componentType: "DOUBLE", type: "SCALAR" },
    pair: { byteOffset: 16, componentType: 5120, type: "VEC2" },
    HIERARCHY: {},
    extensions: {},
    extras: {},
    lone: "not a column",
    ["__proto__"]: [{ polluted: true }, null],
  };
  const t = batchTableProperties(json, binary, 2);
  assert.equal(t.count, 2);
  assert.deepEqual(t.names, ["name", "height", "pair", "__proto__"]);
  const row = t.get(1);
  assert.equal(Object.getPrototypeOf(row), null);
  assert.deepEqual(plain(row), { name: "b", height: 2.5, pair: [3, -4], ["__proto__"]: null });
  assert.deepEqual(plain(t.get(0)).__proto__, { polluted: true });
  assert.equal(({} as any).polluted, undefined);
  assert.deepEqual(plain(batchTableProperties(null, undefined, 3).get(2)), {});
});

test("batchTableProperties refuses references past the binary, bad types and IDs out of range", () => {
  const binary = new Uint8Array(8);
  assert.throws(() => batchTableProperties({ a: { byteOffset: 4, componentType: "FLOAT", type: "VEC2" } }, binary, 1), /runs past/);
  assert.throws(() => batchTableProperties({ a: { byteOffset: 0, componentType: "FLOAT", type: "SCALAR" } }, undefined, 1), /runs past/);
  assert.throws(() => batchTableProperties({ a: { byteOffset: 0, componentType: "LONG", type: "SCALAR" } }, binary, 1), /bad type/);
  assert.throws(() => batchTableProperties({ a: { byteOffset: 0, componentType: "FLOAT", type: "VEC5" } }, binary, 1), /bad type/);
  assert.throws(() => batchTableProperties({}, binary, MAX_FEATURES + 1), /bad feature count/);
  assert.throws(() => batchTableProperties({}, binary, 2).get(2), RangeError);
  assert.throws(() => batchTableProperties({}, binary, 2).get(-1), RangeError);
});

/** A one-table metadata of `properties` (class property, table property, its views' bytes in order). */
function metadata(count: number, properties: Record<string, [Record<string, unknown>, Record<string, unknown>, (Uint8Array | undefined)[]]>, enums = {}): StructuralMetadata {
  const views: Record<number, Uint8Array> = {};
  const classProperties: Record<string, unknown> = Object.create(null);
  const tableProperties: Record<string, unknown> = Object.create(null);
  let next = 0;
  for (const [name, [def, p, data]] of Object.entries(properties)) {
    classProperties[name] = def;
    const t: Record<string, unknown> = { ...p };
    for (const [i, key] of ["values", "arrayOffsets", "stringOffsets"].entries()) {
      if (!data[i]) continue;
      views[next] = data[i];
      t[key] = next++;
    }
    tableProperties[name] = t;
  }
  return { schema: { classes: { c: { properties: classProperties } }, enums }, propertyTables: [{ class: "c", count, properties: tableProperties }], bufferViews: views };
}

test("propertyTableProperties reads every type, arrays, enums, strings and booleans", () => {
  const text = new TextEncoder().encode("ab東京");
  const m = metadata(
    2,
    {
      u16: [{ type: "SCALAR", componentType: "UINT16" }, {}, [bytes(new Uint16Array([7, 65535]))]],
      i64: [{ type: "SCALAR", componentType: "INT64" }, {}, [bytes(new BigInt64Array([-(2n ** 63n), 5n]))]],
      vec2: [{ type: "VEC2", componentType: "FLOAT32" }, {}, [bytes(new Float32Array([0.5, 1, 2, 3]))]],
      mat2: [{ type: "MAT2", componentType: "INT8" }, {}, [bytes(new Int8Array([1, 2, 3, 4, 5, 6, 7, 8]))]],
      fixed: [{ type: "SCALAR", componentType: "UINT8", array: true, count: 2 }, {}, [new Uint8Array([1, 2, 3, 4])]],
      variable: [{ type: "VEC2", componentType: "INT16", array: true }, { arrayOffsetType: "UINT8" }, [bytes(new Int16Array([1, 2, 3, 4, 5, 6])), new Uint8Array([0, 0, 3])]],
      name: [{ type: "STRING" }, { stringOffsetType: "UINT16" }, [text, undefined, bytes(new Uint16Array([0, 2, text.length]))]],
      names: [{ type: "STRING", array: true }, {}, [text, bytes(new Uint32Array([0, 1, 3])), bytes(new Uint32Array([0, 1, 2, text.length]))]],
      flag: [{ type: "BOOLEAN" }, {}, [new Uint8Array([0b10])]],
      flags: [{ type: "BOOLEAN", array: true, count: 3 }, {}, [new Uint8Array([0b101110])]],
      kind: [{ type: "ENUM", enumType: "k" }, {}, [new Uint8Array([2, 9])]],
      kinds: [{ type: "ENUM", enumType: "k", array: true }, {}, [new Uint8Array([1, 2, 1]), bytes(new Uint32Array([0, 2, 3]))]],
    },
    { k: { valueType: "UINT8", values: [{ name: "one", value: 1 }, { name: "two", value: 2 }] } },
  );
  const t = propertyTableProperties(m, 0);
  assert.equal(t.count, 2);
  assert.deepEqual(t.get(0), Object.assign(Object.create(null), {
    u16: 7, i64: -(2n ** 63n), vec2: [0.5, 1], mat2: [1, 2, 3, 4], fixed: [1, 2], variable: [], name: "ab", names: ["a"],
    flag: false, flags: [false, true, true], kind: "two", kinds: ["one", "two"],
  }));
  assert.deepEqual(t.get(1), Object.assign(Object.create(null), {
    u16: 65535, i64: 5n, vec2: [2, 3], mat2: [5, 6, 7, 8], fixed: [3, 4], variable: [[1, 2], [3, 4], [5, 6]], name: "東京", names: ["b", "東京"],
    flag: true, flags: [true, false, true], kind: "", kinds: ["one"],
  }));
});

test("propertyTableProperties normalizes, offsets and scales, and gives defaults for noData and missing columns", () => {
  const m = metadata(2, {
    n: [{ type: "VEC2", componentType: "INT8", normalized: true, offset: [1, 0], scale: [2, 1] }, {}, [new Uint8Array([127, 0x80, 0, 0])]],
    f: [{ type: "SCALAR", componentType: "FLOAT64", offset: 1, scale: 1 }, { offset: 10, scale: 2 }, [bytes(new Float64Array([1, 2]))]],
    i: [{ type: "SCALAR", componentType: "INT32", offset: 100 }, {}, [bytes(new Int32Array([1, 2]))]],
    nd: [{ type: "SCALAR", componentType: "UINT8", noData: 255, default: 0 }, {}, [new Uint8Array([255, 4])]],
    gone: [{ type: "SCALAR", componentType: "UINT8", noData: 4 }, {}, [new Uint8Array([4, 5])]],
    s: [{ type: "STRING", noData: "", default: "none" }, {}, [new Uint8Array([0x78]), undefined, bytes(new Uint32Array([0, 0, 1]))]],
  });
  (m.schema.classes.c.properties as Record<string, unknown>).absent = { type: "SCALAR", componentType: "UINT8", default: 9 };
  (m.schema.classes.c.properties as Record<string, unknown>).absentNoDefault = { type: "SCALAR", componentType: "UINT8" };
  const t = propertyTableProperties(m, 0);
  assert.deepEqual(plain(t.get(0)), { n: [3, -1], f: 12, i: 1, nd: 0, s: "none", absent: 9 });
  assert.deepEqual(plain(t.get(1)), { n: [1, 0], f: 14, i: 2, nd: 4, gone: 5, s: "x", absent: 9 });
});

test("propertyTableProperties refuses bad tables, views and offsets", () => {
  const ok = () => metadata(2, { a: [{ type: "SCALAR", componentType: "UINT16" }, {}, [new Uint8Array(4)]] });
  const edit = (f: (m: StructuralMetadata) => void) => {
    const m = ok();
    f(m);
    return () => propertyTableProperties(m, 0);
  };
  assert.doesNotThrow(edit(() => {}));
  assert.throws(() => propertyTableProperties(ok(), 1), /no property table/);
  assert.throws(edit((m) => (m.propertyTables[0].class = "__proto__")), /no schema class/);
  assert.throws(edit((m) => (m.propertyTables[0].count = 3)), /runs past/);
  assert.throws(edit((m) => (m.propertyTables[0].count = 1.5)), /bad feature count/);
  assert.throws(edit((m) => (m.propertyTables[0].properties.a.values = 7)), /no buffer view/);
  assert.throws(edit((m) => (m.schema.classes.c.properties.a.componentType = "UINT128")), /bad type/);
  assert.throws(edit((m) => Object.assign(m.schema.classes.c.properties.a, { array: true, count: 0 })), /bad count/);
  assert.throws(edit((m) => Object.assign(m.schema.classes.c.properties.a, { type: "ENUM", enumType: "x" })), /no enum/);
  const strings = (offsets: number[], type = "UINT32") =>
    metadata(2, { s: [{ type: "STRING" }, { stringOffsetType: type }, [new Uint8Array(3), undefined, bytes(new Uint32Array(offsets))]] });
  assert.throws(() => propertyTableProperties(strings([0, 2, 1]), 0), /bad offsets/);
  assert.throws(() => propertyTableProperties(strings([0, 1, 4]), 0), /bad offsets/);
  assert.throws(() => propertyTableProperties(strings([0, 1]), 0), /runs past/);
  assert.throws(() => propertyTableProperties(strings([0, 1, 2], "INT32"), 0), /bad offset type/);
  const arrays = metadata(1, { v: [{ type: "SCALAR", componentType: "UINT8", array: true }, {}, [new Uint8Array(2), bytes(new Uint32Array([0, 3]))]] });
  assert.throws(() => propertyTableProperties(arrays, 0), /runs past/);
});

const gltfJson = (json: object) => new TextEncoder().encode(JSON.stringify({ asset: { version: "2.0" }, ...json }));
const uri = (...arrays: ArrayBufferView[]) => `data:application/octet-stream;base64,${Buffer.from(bytes(...arrays)).toString("base64")}`;
const noLoad = async () => new Uint8Array();

test("readGltf keeps feature IDs and EXT_structural_metadata's tables", async () => {
  const positions = new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]);
  const ids = new Uint16Array([1, 0, 7, 0]);
  const values = new Uint8Array([10, 20, 0, 0]);
  const gltf = {
    extensionsRequired: ["EXT_mesh_features", "EXT_structural_metadata"],
    buffers: [{ byteLength: 48, uri: uri(positions, ids, values) }],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: 36 },
      { buffer: 0, byteOffset: 36, byteLength: 6 },
      { buffer: 0, byteOffset: 44, byteLength: 2 },
    ],
    accessors: [
      { bufferView: 0, componentType: 5126, type: "VEC3", count: 3 },
      { bufferView: 1, componentType: 5123, type: "SCALAR", count: 3 },
    ],
    meshes: [
      { primitives: [{ attributes: { POSITION: 0, _FEATURE_ID_0: 1 }, extensions: { EXT_mesh_features: { featureIds: [{ featureCount: 2, attribute: 0, propertyTable: 0, nullFeatureId: 7 }, { featureCount: 3 }, { featureCount: 2, texture: { index: 0 } }] } } }] },
      { primitives: [{ attributes: { POSITION: 0, _BATCHID: 1 } }, { attributes: { POSITION: 0 } }] },
    ],
    nodes: [{ mesh: 0 }, { mesh: 1 }],
    scenes: [{ nodes: [0, 1] }],
    extensions: { EXT_structural_metadata: { schema: { classes: { c: { properties: { v: { type: "SCALAR", componentType: "UINT8" } } } } }, propertyTables: [{ class: "c", count: 2, properties: { v: { values: 2 } } }] } },
  };
  const model = await readGltf(gltfJson(gltf), noLoad);
  const [features, batched, plainPrimitive] = model.primitives;
  assert.equal(features.featureIds!.length, 2);
  const [byAttribute, implicit] = features.featureIds!;
  assert.equal(byAttribute.attribute, features.attributes._FEATURE_ID_0);
  assert.deepEqual([byAttribute.featureCount, byAttribute.propertyTable, byAttribute.nullFeatureId], [2, 0, 7]);
  assert.deepEqual([0, 1, 2].map((v) => featureId(byAttribute, v)), [1, 0, undefined]);
  assert.deepEqual(implicit.implicit, { offset: 0, repeat: 1 });
  assert.deepEqual([0, 1, 2].map((v) => featureId(implicit, v)), [0, 1, 2]);
  assert.deepEqual(batched.featureIds, [{ attribute: batched.attributes._BATCHID }]);
  assert.equal(plainPrimitive.featureIds, undefined);
  assert.deepEqual([...model.metadata!.bufferViews[2]], [10, 20]);
  assert.equal(model.metadata!.bufferViews[2].buffer.byteLength, 2);
  assert.deepEqual(plain(propertyTableProperties(model.metadata!, 0).get(1)), { v: 20 });

  const broken = structuredClone(gltf);
  broken.meshes[0].primitives[0].extensions.EXT_mesh_features.featureIds[0].attribute = 3;
  await assert.rejects(readGltf(gltfJson(broken), noLoad), /no feature ID attribute/);
  const pastBuffer = structuredClone(gltf);
  pastBuffer.extensions.EXT_structural_metadata.propertyTables[0].properties.v.values = 9;
  await assert.rejects(readGltf(gltfJson(pastBuffer), noLoad), /no buffer view 9/);
});
