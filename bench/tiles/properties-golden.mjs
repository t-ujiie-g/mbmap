// npm/src/tiles/properties.ts vs @loaders.gl 4.5.4's Tile3DBatchTable (PLATEAU's and synthetic b3dm) and
// EXT_structural_metadata (glbs written here, also checked against the values written: alone where loaders.gl
// departs from the spec, `deviation`); hostile tables must throw. Writes bench/results/tiles-properties.json.
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { parse } from "@loaders.gl/core";
import { Tiles3DLoader, Tile3DBatchTable } from "@loaders.gl/3d-tiles";
import { GLTFLoader } from "@loaders.gl/gltf";
import { Document, NodeIO } from "@gltf-transform/core";
import { batchTableProperties, featureId, propertyTableProperties } from "../../npm/src/tiles/properties.ts";
import { readGltf } from "../../npm/src/model/gltf.ts";
import { ROOT } from "../lib/root.mjs";

function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(7);

/** Deep equality with bigints, typed arrays read as arrays and -0 equal to 0. */
function equal(a, b) {
  if (ArrayBuffer.isView(a)) a = Array.from(a);
  if (ArrayBuffer.isView(b)) b = Array.from(b);
  if (Array.isArray(a) || Array.isArray(b)) return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => equal(x, b[i]));
  if (a !== null && b !== null && typeof a === "object" && typeof b === "object") {
    const ka = Object.keys(a);
    return ka.length === Object.keys(b).length && ka.every((k) => Object.hasOwn(b, k) && equal(a[k], b[k]));
  }
  return a === b || (Number.isNaN(a) && Number.isNaN(b));
}
const show = (v) => JSON.stringify(v, (_, x) => (typeof x === "bigint" ? `${x}n` : ArrayBuffer.isView(x) ? Array.from(x) : x));
const throws = (f) => {
  try {
    f();
    return false;
  } catch {
    return true;
  }
};

const results = [];
let failed = 0;
const record = (r) => {
  if (!r.same) failed++;
  results.push(r);
};

// Batch tables.
const doc = new Document();
const pos = doc.createAccessor().setType("VEC3").setArray(new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 0])).setBuffer(doc.createBuffer());
doc.createScene().addChild(doc.createNode().setMesh(doc.createMesh().addPrimitive(doc.createPrimitive().setAttribute("POSITION", pos))));
const tinyGlb = await new NodeIO().writeBinary(doc);

const pad = (bytes, to, fill = 0x20) => {
  const out = new Uint8Array(Math.ceil(bytes.length / to) * to).fill(fill);
  out.set(bytes);
  return out;
};
function b3dm(featureTable, batchJson, batchBinary) {
  const ft = pad(new TextEncoder().encode(JSON.stringify(featureTable)), 8);
  const bt = pad(new TextEncoder().encode(JSON.stringify(batchJson)), 8);
  const bb = pad(batchBinary, 8, 0);
  const out = new Uint8Array(28 + ft.length + bt.length + bb.length + tinyGlb.length);
  const v = new DataView(out.buffer);
  [0x6d643362, 1, out.length, ft.length, 0, bt.length, bb.length].forEach((x, i) => v.setUint32(i * 4, x, true));
  out.set(ft, 28);
  out.set(bt, 28 + ft.length);
  out.set(bb, 28 + ft.length + bt.length);
  out.set(tinyGlb, 28 + ft.length + bt.length + bb.length);
  return out;
}
/** The b3dm's batch length, batch table JSON and binary, by its header. */
function tables(bytes) {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const [ftJson, ftBin, btJson, btBin] = [12, 16, 20, 24].map((at) => v.getUint32(at, true));
  const text = (at, n) => (n ? JSON.parse(new TextDecoder().decode(bytes.subarray(at, at + n))) : null);
  const btAt = 28 + ftJson + ftBin;
  return { batchLength: text(28, ftJson).BATCH_LENGTH ?? 0, json: text(btAt, btJson), binary: bytes.subarray(btAt + btJson, btAt + btJson + btBin) };
}

const GL_COMPONENTS = {
  BYTE: [Int8Array, -128, 127],
  UNSIGNED_BYTE: [Uint8Array, 0, 255],
  SHORT: [Int16Array, -32768, 32767],
  UNSIGNED_SHORT: [Uint16Array, 0, 65535],
  INT: [Int32Array, -(2 ** 31), 2 ** 31 - 1],
  UNSIGNED_INT: [Uint32Array, 0, 2 ** 32 - 1],
  FLOAT: [Float32Array],
  DOUBLE: [Float64Array],
};
const SIZES = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT2: 4, MAT3: 9, MAT4: 16 };

function syntheticB3dm(count) {
  const json = {
    name: Array.from({ length: count }, (_, i) => `建物 ${i}`),
    height: Array.from({ length: count }, () => rand() * 100),
    mixed: Array.from({ length: count }, (_, i) => [null, { a: [1, 2], b: "x" }, true, "s", 3][i % 5]),
    short: [1, 2],
    ["__proto__"]: Array.from({ length: count }, (_, i) => ({ polluted: i })),
    constructor: Array.from({ length: count }, (_, i) => i),
    HIERARCHY: { classes: [] },
    extras: { note: "not a property" },
  };
  const parts = [];
  let at = 0;
  for (const [componentType, [Type, lo, hi]] of Object.entries(GL_COMPONENTS)) {
    for (const [type, size] of Object.entries(SIZES)) {
      const values = new Type(count * size);
      for (let i = 0; i < values.length; i++) values[i] = lo === undefined ? (rand() - 0.5) * 1e6 : lo + Math.floor(rand() * (hi - lo + 1));
      const bytes = new Uint8Array(values.buffer);
      json[`${componentType}_${type}`] = { byteOffset: at, componentType, type };
      parts.push(pad(bytes, 8, 0));
      at += parts.at(-1).length;
    }
  }
  json.numeric = { byteOffset: 0, componentType: 5126, type: "SCALAR" };
  const binary = new Uint8Array(at);
  let o = 0;
  for (const p of parts) {
    binary.set(p, o);
    o += p.length;
  }
  return b3dm({ BATCH_LENGTH: count }, JSON.parse(JSON.stringify(json)), binary);
}

const b3dms = [];
const plateau = path.join(ROOT, "bench/fixtures/plateau-chiyoda/data");
if (existsSync(plateau)) for (const f of (await readdir(plateau)).filter((f) => f.endsWith(".b3dm")).sort()) b3dms.push([`plateau/${f}`, new Uint8Array(await readFile(path.join(plateau, f)))]);
else console.log("plateau-chiyoda fixture missing: synthetic batch tables only");
b3dms.push(["synthetic-1", syntheticB3dm(1)], ["synthetic-7", syntheticB3dm(7)], ["synthetic-40", syntheticB3dm(40)]);

let batchFeatures = 0;
let batchValues = 0;
const batchDiffers = [];
const inheritedNames = new Set();
for (const [name, bytes] of b3dms) {
  const theirs = await parse(bytes, Tiles3DLoader, { "3d-tiles": { loadGLTF: false } });
  const table = new Tile3DBatchTable(theirs.batchTableJson, theirs.batchTableBinary, theirs.featureTableJson.BATCH_LENGTH ?? 0);
  const { batchLength, json, binary } = tables(bytes);
  const ours = batchTableProperties(json, binary, batchLength);
  const names = table.getPropertyNames(0);
  // loaders.gl skips names found on Object.prototype (it looks them up in a plain object); those are checked against the JSON.
  const inherited = ours.names.filter((k) => k in Object.prototype);
  const listed = ours.names.filter((k) => !inherited.includes(k));
  if (!equal(listed, names) || ours.count !== table.featureCount) batchDiffers.push({ name, onlyOurs: listed.filter((k) => !names.includes(k)), onlyTheirs: names.filter((k) => !listed.includes(k)) });
  if (inherited.length) inheritedNames.add(inherited.join(", "));
  for (let id = 0; id < ours.count; id++) {
    const row = ours.get(id);
    if (Object.getPrototypeOf(row) !== null) batchDiffers.push({ name, id, prototype: true });
    batchFeatures++;
    for (const key of inherited) if (!equal(row[key], json[key][id])) batchDiffers.push({ name, id, key, ours: show(row[key]), written: show(json[key][id]) });
    for (const key of names) {
      batchValues++;
      const a = row[key];
      const b = table.getProperty(id, key);
      if (!equal(a, b) && batchDiffers.length < 10) batchDiffers.push({ name, id, key, ours: show(a), theirs: show(b) });
    }
  }
}
if ({}.polluted !== undefined) batchDiffers.push({ pollution: true });
record({ part: "batch tables", contents: b3dms.length, features: batchFeatures, values: batchValues, same: batchDiffers.length === 0, differ: batchDiffers, againstJson: [...inheritedNames] });

{
  const { batchLength, json, binary } = tables(syntheticB3dm(4));
  const hostile = {
    "offset past the binary": () => batchTableProperties({ a: { byteOffset: binary.length - 4, componentType: "DOUBLE", type: "SCALAR" } }, binary, batchLength),
    "negative offset": () => batchTableProperties({ a: { byteOffset: -8, componentType: "FLOAT", type: "SCALAR" } }, binary, batchLength),
    "no binary": () => batchTableProperties({ a: { byteOffset: 0, componentType: "FLOAT", type: "SCALAR" } }, undefined, batchLength),
    "bad component type": () => batchTableProperties({ a: { byteOffset: 0, componentType: "LONG", type: "SCALAR" } }, binary, batchLength),
    "bad type": () => batchTableProperties({ a: { byteOffset: 0, componentType: "FLOAT", type: "VEC9" } }, binary, batchLength),
    "huge batch length": () => batchTableProperties(json, binary, 2 ** 31),
    "batch id out of range": () => batchTableProperties(json, binary, batchLength).get(batchLength),
  };
  const kept = Object.entries(hostile).filter(([, f]) => !throws(f)).map(([k]) => k);
  record({ part: "hostile batch tables", cases: Object.keys(hostile).length, same: kept.length === 0, notRefused: kept });
}

// EXT_structural_metadata and EXT_mesh_features.
const META = {
  INT8: [Int8Array, -128, 127],
  UINT8: [Uint8Array, 0, 255],
  INT16: [Int16Array, -32768, 32767],
  UINT16: [Uint16Array, 0, 65535],
  INT32: [Int32Array, -(2 ** 31), 2 ** 31 - 1],
  UINT32: [Uint32Array, 0, 2 ** 32 - 1],
  INT64: [BigInt64Array, -(2n ** 63n), 2n ** 63n - 1n],
  UINT64: [BigUint64Array, 0n, 2n ** 64n - 1n],
  FLOAT32: [Float32Array],
  FLOAT64: [Float64Array],
};
const INT_MAX = { INT8: 127, UINT8: 255, INT16: 32767, UINT16: 65535, INT32: 2147483647, UINT32: 4294967295, INT64: 2 ** 63 - 1, UINT64: 2 ** 64 - 1 };
const COMPONENTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT2: 4, MAT3: 9, MAT4: 16 };

function component(kind) {
  const [, lo, hi] = META[kind];
  if (lo === undefined) return kind === "FLOAT32" ? Math.fround((rand() - 0.5) * 1e4) : (rand() - 0.5) * 1e9;
  if (typeof lo === "bigint") {
    const r = rand();
    if (r < 0.2) return lo;
    if (r < 0.4) return hi;
    return lo + ((BigInt(Math.floor(rand() * 2 ** 32)) << 32n) | BigInt(Math.floor(rand() * 2 ** 32))) % (hi - lo);
  }
  return lo + Math.floor(rand() * (hi - lo + 1));
}
const element = (kind, type) => (COMPONENTS[type] === 1 ? component(kind) : Array.from({ length: COMPONENTS[type] }, () => component(kind)));
const bytesOf = (kind, flat) => {
  const out = new META[kind][0](flat.length);
  flat.forEach((v, i) => (out[i] = v));
  return new Uint8Array(out.buffer);
};
const offsetBytes = (type, list) => bytesOf(type, type === "UINT64" ? list.map(BigInt) : list);

/** One property's buffer views (values, arrayOffsets, stringOffsets) from its rows, as the spec lays them out. */
function encode(def, rows, enums, options = {}) {
  const variable = def.array && def.count === undefined;
  const elements = def.array ? rows.flat(1) : rows;
  const views = {};
  if (variable) {
    let at = 0;
    views.arrayOffsets = offsetBytes(options.arrayOffsetType ?? "UINT32", [0, ...rows.map((r) => (at += r.length))]);
  }
  if (def.type === "STRING") {
    const texts = elements.map((s) => new TextEncoder().encode(s));
    const skip = options.stringStart ?? 0;
    let at = skip;
    views.stringOffsets = offsetBytes(options.stringOffsetType ?? "UINT32", [skip, ...texts.map((t) => (at += t.length))]);
    views.values = new Uint8Array(at);
    at = skip;
    for (const t of texts) {
      views.values.set(t, at);
      at += t.length;
    }
  } else if (def.type === "BOOLEAN") {
    views.values = new Uint8Array(Math.ceil(elements.length / 8));
    elements.forEach((b, i) => (views.values[i >> 3] |= (b ? 1 : 0) << (i & 7)));
  } else if (def.type === "ENUM") {
    const e = enums[def.enumType];
    views.values = bytesOf(e.valueType ?? "UINT16", elements.map((n) => e.values.find((v) => v.name === n).value).map((v) => (/64/.test(e.valueType) ? BigInt(v) : v)));
  } else {
    views.values = bytesOf(def.componentType, elements.flat());
  }
  return views;
}

/** The value the spec gives a raw row: normalization, offset and scale, noData's default. */
function expected(def, tableProperty, raw) {
  if (def.noData !== undefined && equal(raw, def.noData)) return def.default;
  const max = INT_MAX[def.componentType];
  const normalize = def.normalized && max !== undefined;
  const offset = tableProperty.offset ?? def.offset;
  const scale = tableProperty.scale ?? def.scale;
  const shift = COMPONENTS[def.type] && !(def.array && def.count === undefined) && (/FLOAT/.test(def.componentType) || normalize) && (offset !== undefined || scale !== undefined);
  const go = (v, o, s) =>
    Array.isArray(v)
      ? v.map((x, i) => go(x, Array.isArray(o) ? o[i] : o, Array.isArray(s) ? s[i] : s))
      : ((x) => (shift ? (o ?? 0) + (s ?? 1) * x : x))(normalize ? Math.max(Number(v) / max, -1) : v);
  return COMPONENTS[def.type] ? go(raw, offset, scale) : raw;
}

/** A glb of one triangle, its feature IDs, and one property table of `rows` for each property case. */
function metadataGlb(count, cases, enums, vertexIds) {
  const chunks = [];
  const bufferViews = [];
  const addView = (bytes) => {
    const at = chunks.reduce((n, c) => n + c.length, 0);
    chunks.push(pad(bytes, 8, 0));
    bufferViews.push({ buffer: 0, byteOffset: at, byteLength: bytes.length });
    return bufferViews.length - 1;
  };
  addView(new Uint8Array(new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]).buffer));
  addView(new Uint8Array(new Uint16Array([...vertexIds, 0]).buffer).subarray(0, 6));
  const properties = Object.create(null);
  const tableProperties = Object.create(null);
  for (const c of cases) {
    properties[c.name] = c.def;
    const views = encode(c.def, c.rows, enums, c.options);
    const p = { ...c.table };
    if (c.options?.arrayOffsetType) p.arrayOffsetType = c.options.arrayOffsetType;
    if (c.options?.stringOffsetType) p.stringOffsetType = c.options.stringOffsetType;
    for (const [k, bytes] of Object.entries(views)) p[k] = addView(bytes);
    tableProperties[c.name] = p;
  }
  const json = {
    asset: { version: "2.0" },
    extensionsUsed: ["EXT_mesh_features", "EXT_structural_metadata"],
    buffers: [{ byteLength: chunks.reduce((n, c) => n + c.length, 0) }],
    bufferViews,
    accessors: [
      { bufferView: 0, componentType: 5126, type: "VEC3", count: 3, min: [0, 0, 0], max: [1, 1, 0] },
      { bufferView: 1, componentType: 5123, type: "SCALAR", count: 3 },
    ],
    meshes: [
      {
        primitives: [
          {
            attributes: { POSITION: 0, _FEATURE_ID_0: 1 },
            extensions: { EXT_mesh_features: { featureIds: [{ featureCount: count, attribute: 0, propertyTable: 0, nullFeatureId: 9 }, { featureCount: 3, label: "vertices" }] } },
          },
        ],
      },
    ],
    nodes: [{ mesh: 0 }],
    scenes: [{ nodes: [0] }],
    extensions: { EXT_structural_metadata: { schema: { id: "s", classes: { c: { properties } }, enums }, propertyTables: [{ class: "c", count, properties: tableProperties }] } },
  };
  const text = pad(new TextEncoder().encode(JSON.stringify(json)), 4);
  const bin = new Uint8Array(json.buffers[0].byteLength);
  let at = 0;
  for (const c of chunks) {
    bin.set(c, at);
    at += c.length;
  }
  const out = new Uint8Array(12 + 8 + text.length + 8 + bin.length);
  const v = new DataView(out.buffer);
  v.setUint32(0, 0x46546c67, true);
  v.setUint32(4, 2, true);
  v.setUint32(8, out.length, true);
  v.setUint32(12, text.length, true);
  v.setUint32(16, 0x4e4f534a, true);
  out.set(text, 20);
  v.setUint32(20 + text.length, bin.length, true);
  v.setUint32(24 + text.length, 0x004e4942, true);
  out.set(bin, 28 + text.length);
  return { glb: out, json };
}

const ENUMS = {
  species: { values: [{ name: "Unknown", value: 0 }, { name: "Oak", value: 3 }, { name: "Pine", value: 70 }] },
  small: { valueType: "UINT8", values: [{ name: "A", value: 1 }, { name: "B", value: 200 }] },
  signed: { valueType: "INT32", values: [{ name: "neg", value: -5 }, { name: "pos", value: 123456 }] },
  wide: { valueType: "UINT64", values: [{ name: "big", value: 7 }, { name: "small", value: 1 }] },
};
const enumNames = (e) => ENUMS[e].values.map((v) => v.name);
const pick = (list) => list[Math.floor(rand() * list.length)];
const WORDS = ["", "a", "東京", "Tōkyō 駅", "😀 emoji", "long text with spaces"];

/** Property cases: name, class property, its table property's extra fields and rows; `deviation` when loaders.gl reads it against the spec. */
function cases(count) {
  const out = [];
  const add = (name, def, row, extra = {}) => out.push({ name, def, rows: Array.from({ length: count }, (_, i) => row(i)), table: extra.table ?? {}, options: extra.options, deviation: extra.deviation });
  for (const kind of Object.keys(META)) {
    for (const type of Object.keys(COMPONENTS)) add(`${kind}_${type}`, { type, componentType: kind }, () => element(kind, type));
    add(`${kind}_fixed`, { type: "SCALAR", componentType: kind, array: true, count: 3 }, () => [0, 1, 2].map(() => component(kind)));
    add(`${kind}_variable`, { type: "SCALAR", componentType: kind, array: true }, () => Array.from({ length: Math.floor(rand() * 4) }, () => component(kind)), {
      deviation: META[kind][0].BYTES_PER_ELEMENT > 1 ? "array offsets read as byte offsets, not element indices" : undefined,
    });
    if (INT_MAX[kind] !== undefined) add(`${kind}_normalized`, { type: "VEC2", componentType: kind, normalized: true }, () => element(kind, "VEC2"));
  }
  add("vec3_fixed", { type: "VEC3", componentType: "FLOAT32", array: true, count: 2 }, () => [element("FLOAT32", "VEC3"), element("FLOAT32", "VEC3")], { deviation: "fixed arrays of vectors sliced by components" });
  add("mat2_variable", { type: "MAT2", componentType: "INT16", array: true }, () => Array.from({ length: Math.floor(rand() * 3) }, () => element("INT16", "MAT2")), { deviation: "variable arrays of matrices sliced by components" });
  add("variable_uint8_offsets", { type: "SCALAR", componentType: "UINT8", array: true }, () => [component("UINT8")], { options: { arrayOffsetType: "UINT8" } });
  add("variable_uint16_offsets", { type: "SCALAR", componentType: "INT8", array: true }, () => [component("INT8"), component("INT8")], { options: { arrayOffsetType: "UINT16" } });
  add("variable_uint64_offsets", { type: "SCALAR", componentType: "UINT8", array: true }, () => [component("UINT8")], { options: { arrayOffsetType: "UINT64" }, deviation: "UINT64 offsets dropped" });
  add("float_offset_scale", { type: "SCALAR", componentType: "FLOAT32", offset: 10, scale: 2 }, () => component("FLOAT32"));
  add("vec3_table_override", { type: "VEC3", componentType: "FLOAT64", offset: [1, 2, 3], scale: [1, 1, 1] }, () => element("FLOAT64", "VEC3"), { table: { offset: [-1, 0, 1], scale: [2, 3, 4] } });
  add("normalized_offset_scale", { type: "VEC2", componentType: "UINT8", normalized: true, offset: [0, 100], scale: [10, -10] }, () => element("UINT8", "VEC2"));
  add("fixed_offset_scale", { type: "SCALAR", componentType: "FLOAT32", array: true, count: 3, offset: [1, 2, 3], scale: [2, 2, 2] }, () => [0, 1, 2].map(() => component("FLOAT32")));
  add("int_ignores_offset", { type: "SCALAR", componentType: "INT32", offset: 5 }, () => component("INT32"));
  add("no_data", { type: "SCALAR", componentType: "INT16", noData: -1, default: 0 }, (i) => (i % 3 === 0 ? -1 : component("INT16")));
  add("no_data_no_default", { type: "SCALAR", componentType: "UINT8", noData: 255 }, (i) => (i % 2 ? 255 : 1));
  add("string", { type: "STRING" }, () => pick(WORDS));
  add("string_uint8_offsets", { type: "STRING" }, () => pick(WORDS.slice(0, 3)), { options: { stringOffsetType: "UINT8" } });
  add("string_uint16_offsets", { type: "STRING" }, () => pick(WORDS), { options: { stringOffsetType: "UINT16" } });
  add("string_uint64_offsets", { type: "STRING" }, () => pick(WORDS), { options: { stringOffsetType: "UINT64" }, deviation: "UINT64 offsets dropped" });
  add("string_late_start", { type: "STRING" }, () => pick(WORDS), { options: { stringStart: 3 }, deviation: "string offsets taken from 0" });
  add("string_no_data", { type: "STRING", noData: "", default: "none" }, () => pick(WORDS));
  add("string_fixed", { type: "STRING", array: true, count: 2 }, () => [pick(WORDS), pick(WORDS)], { deviation: "string arrays not read (throws)" });
  add("string_variable", { type: "STRING", array: true }, () => Array.from({ length: Math.floor(rand() * 3) }, () => pick(WORDS)), { deviation: "string arrays not read (throws)" });
  add("boolean", { type: "BOOLEAN" }, () => rand() < 0.5, { deviation: "booleans not read (throws)" });
  add("boolean_fixed", { type: "BOOLEAN", array: true, count: 3 }, () => [rand() < 0.5, rand() < 0.5, rand() < 0.5], { deviation: "booleans not read (throws)" });
  add("boolean_variable", { type: "BOOLEAN", array: true }, () => Array.from({ length: Math.floor(rand() * 4) }, () => rand() < 0.5), { deviation: "booleans not read (throws)" });
  add("enum", { type: "ENUM", enumType: "species" }, () => pick(enumNames("species")));
  add("enum_uint8", { type: "ENUM", enumType: "small" }, () => pick(enumNames("small")));
  add("enum_int32", { type: "ENUM", enumType: "signed" }, () => pick(enumNames("signed")));
  add("enum_uint64", { type: "ENUM", enumType: "wide" }, () => pick(enumNames("wide")), { deviation: "64-bit enum values give empty names" });
  add("enum_fixed", { type: "ENUM", enumType: "species", array: true, count: 2 }, () => [pick(enumNames("species")), pick(enumNames("species"))]);
  add("enum_variable_uint8", { type: "ENUM", enumType: "small", array: true }, () => Array.from({ length: Math.floor(rand() * 3) }, () => pick(enumNames("small"))));
  add("enum_variable", { type: "ENUM", enumType: "species", array: true }, () => Array.from({ length: 1 + Math.floor(rand() * 3) }, () => pick(enumNames("species"))), {
    deviation: "array offsets read as byte offsets, not element indices",
  });
  add("enum_no_data", { type: "ENUM", enumType: "species", noData: "Unknown", default: "Oak" }, () => pick(enumNames("species")));
  add("__proto__", { type: "SCALAR", componentType: "UINT8" }, () => component("UINT8"));
  return out;
}

/** loaders.gl's decoded column, taken per row and through the spec's transforms. */
function theirsRow(c, data, id) {
  const n = COMPONENTS[c.def.type] ?? 1;
  let raw;
  if (c.def.array) raw = data[id] === undefined ? undefined : Array.from(data[id]);
  else if (c.def.type === "STRING" || c.def.type === "ENUM" || n === 1) raw = data[id];
  else raw = Array.from(data.slice(id * n, (id + 1) * n));
  return raw === undefined ? undefined : expected(c.def, c.table, raw);
}

let metadataValues = 0;
const metadataDiffers = [];
const deviations = new Map();
for (const count of [1, 5, 33]) {
  for (const c of cases(count)) {
    const { glb, json } = metadataGlb(count, [c], ENUMS, [0, count - 1, 9]);
    const model = await readGltf(glb, async () => new Uint8Array());
    const ours = propertyTableProperties(model.metadata, 0);
    let theirs;
    let theirError;
    try {
      const gltf = await parse(glb.slice().buffer, GLTFLoader, { gltf: { loadBuffers: true, loadImages: false, postProcess: false } });
      theirs = gltf.json.extensions.EXT_structural_metadata.propertyTables[0].properties[c.name].data;
    } catch (e) {
      theirError = String(e.message ?? e);
    }
    let loadersSame = theirs !== undefined;
    for (let id = 0; id < count; id++) {
      metadataValues++;
      const row = ours.get(id);
      const want = expected(c.def, json.extensions.EXT_structural_metadata.propertyTables[0].properties[c.name], c.rows[id]);
      const mine = Object.hasOwn(row, c.name) ? row[c.name] : undefined;
      if (!equal(mine, want) && metadataDiffers.length < 20) metadataDiffers.push({ case: c.name, count, id, ours: show(mine), written: show(want) });
      if (theirs !== undefined && !equal(mine, theirsRow(c, theirs, id))) {
        loadersSame = false;
        if (!c.deviation && metadataDiffers.length < 20) metadataDiffers.push({ case: c.name, count, id, ours: show(mine), loaders: show(theirsRow(c, theirs, id)) });
      }
    }
    if (!loadersSame && !c.deviation) metadataDiffers.push({ case: c.name, count, loadersError: theirError });
    if (c.deviation) {
      const d = deviations.get(c.name) ?? { case: c.name, deviation: c.deviation, loadersSame: [] };
      d.loadersSame.push(loadersSame);
      deviations.set(c.name, d);
    }
  }
}
record({ part: "property tables", cases: cases(1).length, values: metadataValues, same: metadataDiffers.length === 0, differ: metadataDiffers, againstWritten: [...deviations.values()] });

{
  const count = 6;
  const all = cases(count).filter((c) => !c.deviation);
  const { glb } = metadataGlb(count, all, ENUMS, [2, 9, 5]);
  const model = await readGltf(glb, async () => new Uint8Array());
  const gltf = await parse(glb.slice().buffer, GLTFLoader, { gltf: { loadBuffers: true, loadImages: false, postProcess: false } });
  const theirIds = gltf.json.meshes[0].primitives[0].extensions.EXT_mesh_features.featureIds;
  const [byAttribute, implicit] = model.primitives[0].featureIds;
  const ids = [0, 1, 2].map((v) => featureId(byAttribute, v));
  const ok =
    equal(byAttribute.attribute.data, theirIds[0].data) &&
    equal(ids, [2, undefined, 5]) &&
    equal([0, 1, 2].map((v) => featureId(implicit, v)), [0, 1, 2]) &&
    byAttribute.propertyTable === 0 &&
    byAttribute.featureCount === count &&
    implicit.label === "vertices" &&
    equal(theirIds[1].data, []);
  const ours = propertyTableProperties(model.metadata, 0);
  const tableProperties = gltf.json.extensions.EXT_structural_metadata.propertyTables[0].properties;
  const differ = [];
  for (let id = 0; id < count; id++) {
    const row = ours.get(id);
    for (const c of all) if (!equal(row[c.name], theirsRow(c, tableProperties[c.name].data, id))) differ.push({ case: c.name, id });
  }
  record({ part: "feature IDs and one table of every property", properties: all.length, same: ok && differ.length === 0, differ: differ.slice(0, 10) });
}

{
  const base = () => {
    const { glb, json } = metadataGlb(4, cases(4).filter((c) => ["UINT16_SCALAR", "string", "INT8_variable"].includes(c.name)), ENUMS, [0, 1, 2]);
    return { glb, json };
  };
  /** Reads `json` (edited) with the glb's binary chunk as it was. */
  const reread = async (edit) => {
    const { glb, json } = base();
    const textLength = new DataView(glb.buffer).getUint32(12, true);
    const bin = glb.subarray(20 + textLength);
    edit(json);
    const text = pad(new TextEncoder().encode(JSON.stringify(json)), 4);
    const out = new Uint8Array(20 + text.length + bin.length);
    out.set(glb.subarray(0, 20));
    new DataView(out.buffer).setUint32(8, out.length, true);
    new DataView(out.buffer).setUint32(12, text.length, true);
    out.set(text, 20);
    out.set(bin, 20 + text.length);
    const model = await readGltf(out, async () => new Uint8Array());
    const t = propertyTableProperties(model.metadata, 0);
    for (let id = 0; id < t.count; id++) t.get(id);
  };
  const table = (json) => json.extensions.EXT_structural_metadata.propertyTables[0];
  const hostile = {
    "huge count": (j) => (table(j).count = 2 ** 30),
    "count past the values": (j) => (table(j).count = 40),
    "negative count": (j) => (table(j).count = -1),
    "missing class": (j) => (table(j).class = "nope"),
    "__proto__ class": (j) => (table(j).class = "__proto__"),
    "values view missing": (j) => (table(j).properties.UINT16_SCALAR.values = 99),
    "view past its buffer": (j) => (j.bufferViews[table(j).properties.string.values].byteLength = 1 << 20),
    "string offsets past the values": (j) => (j.bufferViews[table(j).properties.string.values].byteLength = 0),
    "bad offset type": (j) => (table(j).properties.string.stringOffsetType = "INT8"),
    "array offsets past the values": (j) => (j.bufferViews[table(j).properties.INT8_variable.values].byteLength = 0),
    "array offsets short": (j) => (j.bufferViews[table(j).properties.INT8_variable.arrayOffsets].byteLength = 4),
    "bad component type": (j) => (j.extensions.EXT_structural_metadata.schema.classes.c.properties.UINT16_SCALAR.componentType = "UINT128"),
    "bad fixed count": (j) => Object.assign(j.extensions.EXT_structural_metadata.schema.classes.c.properties.UINT16_SCALAR, { array: true, count: 1e9 }),
    "missing enum": (j) => Object.assign(j.extensions.EXT_structural_metadata.schema.classes.c.properties.UINT16_SCALAR, { type: "ENUM", enumType: "nope" }),
    "feature ID attribute missing": (j) => (j.meshes[0].primitives[0].extensions.EXT_mesh_features.featureIds[0].attribute = 4),
  };
  const kept = [];
  for (const [name, edit] of Object.entries(hostile)) {
    try {
      await reread(edit);
      kept.push(name);
    } catch {}
  }
  let decreasing = false;
  {
    const { glb, json } = base();
    const model = await readGltf(glb, async () => new Uint8Array());
    const p = table(json).properties.INT8_variable;
    const offsets = new Uint32Array(model.metadata.bufferViews[p.arrayOffsets].buffer);
    offsets[2] = offsets[1] > 0 ? offsets[1] - 1 : 0;
    offsets[1] = offsets[2] + 1;
    decreasing = throws(() => propertyTableProperties(model.metadata, 0));
  }
  if (!decreasing) kept.push("decreasing array offsets");
  record({ part: "hostile property tables", cases: Object.keys(hostile).length + 1, same: kept.length === 0, notRefused: kept });
}

await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(
  path.join(ROOT, "bench/results/tiles-properties.json"),
  JSON.stringify({ env: { loaders: "@loaders.gl/3d-tiles 4.5.4, @loaders.gl/gltf 4.5.4" }, results }, null, 2) + "\n",
);
for (const r of results) console.log(JSON.stringify(r));
console.log(`tiles properties: ${results.length - failed} of ${results.length} the same`);
process.exit(failed ? 1 : 0);
