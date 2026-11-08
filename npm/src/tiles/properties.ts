// 3D Tiles feature properties for picking: b3dm batch tables (3D Tiles 1.0) and EXT_structural_metadata
// property tables (3D Tiles 1.1, the 3D Metadata binary table format). Import-free.
import type { FeatureIds, StructuralMetadata } from "../model/gltf.ts";

/** A table of `count` features: `names` its columns, `get(id)` one feature's values (a null-prototype object; missing values left out). */
export interface FeatureProperties {
  count: number;
  names: string[];
  get(id: number): Record<string, unknown>;
}

/** Caps on a table: its rows and the elements of one array value. */
export const MAX_FEATURES = 1 << 24;
export const MAX_ARRAY_ELEMENTS = 1 << 20;

type Read = (id: number) => unknown;

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);

function table(count: number, columns: [string, Read][]): FeatureProperties {
  return {
    count,
    names: columns.map(([name]) => name),
    get(id) {
      if (!Number.isInteger(id) || id < 0 || id >= count) throw new RangeError(`no feature ${id}`);
      const out: Record<string, unknown> = Object.create(null);
      for (const [name, read] of columns) {
        const value = read(id);
        if (value !== undefined) out[name] = value;
      }
      return out;
    },
  };
}

function checkCount(count: unknown): number {
  if (!Number.isInteger(count) || (count as number) < 0 || (count as number) > MAX_FEATURES) throw new Error(`bad feature count ${count}`);
  return count as number;
}

const BATCH_COMPONENTS: Record<string, number> = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT2: 4, MAT3: 9, MAT4: 16 };
const GL_NAMES: Record<number, string> = { 5120: "BYTE", 5121: "UNSIGNED_BYTE", 5122: "SHORT", 5123: "UNSIGNED_SHORT", 5124: "INT", 5125: "UNSIGNED_INT", 5126: "FLOAT", 5130: "DOUBLE" };
const BATCH_TYPES: Record<string, string> = {
  BYTE: "INT8",
  UNSIGNED_BYTE: "UINT8",
  SHORT: "INT16",
  UNSIGNED_SHORT: "UINT16",
  INT: "INT32",
  UNSIGNED_INT: "UINT32",
  FLOAT: "FLOAT32",
  DOUBLE: "FLOAT64",
};

/**
 * A b3dm's batch table (3D Tiles 1.0) as loaders.gl's Tile3DBatchTable reads it: JSON arrays indexed by
 * batch ID and binary references `{byteOffset, componentType, type}` into `binary`; HIERARCHY,
 * `extensions` and `extras` are not properties (3DTILES_batch_table_hierarchy is not read).
 */
export function batchTableProperties(json: Record<string, unknown> | null | undefined, binary: Uint8Array | undefined, batchLength: number): FeatureProperties {
  const count = checkCount(batchLength);
  const columns: [string, Read][] = [];
  for (const name of Object.keys(json ?? {})) {
    if (name === "HIERARCHY" || name === "extensions" || name === "extras") continue;
    const value = json![name];
    if (Array.isArray(value)) {
      columns.push([name, (id) => value[id]]);
    } else if (isObject(value) && "byteOffset" in value) {
      const kind = BATCH_TYPES[typeof value.componentType === "number" ? GL_NAMES[value.componentType] : value.componentType];
      const size = BATCH_COMPONENTS[value.type];
      if (!kind || !size) throw new Error(`batch table property ${name} has a bad type`);
      const n = numbers(slice(binary, value.byteOffset, count * size * BYTES[kind], name), kind);
      columns.push([name, size === 1 ? (id) => n(id) : (id) => Array.from({ length: size }, (_, i) => n(id * size + i))]);
    }
  }
  return table(count, columns);
}

function slice(bytes: Uint8Array | undefined, offset: unknown, length: number, name: string): Uint8Array {
  if (!bytes || !Number.isInteger(offset) || (offset as number) < 0 || (offset as number) + length > bytes.length) throw new Error(`property ${name} runs past its buffer`);
  return bytes.subarray(offset as number, (offset as number) + length);
}

const BYTES: Record<string, number> = { INT8: 1, UINT8: 1, INT16: 2, UINT16: 2, INT32: 4, UINT32: 4, INT64: 8, UINT64: 8, FLOAT32: 4, FLOAT64: 8 };
const INT_MAX: Record<string, number> = { INT8: 127, UINT8: 255, INT16: 32767, UINT16: 65535, INT32: 2147483647, UINT32: 4294967295, INT64: 2 ** 63 - 1, UINT64: 2 ** 64 - 1 };

/** Element `i` of `bytes` as `type` (little-endian): a number, or a bigint for 64-bit integers. */
function numbers(bytes: Uint8Array, type: string): (i: number) => number | bigint {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  switch (type) {
    case "INT8": return (i) => v.getInt8(i);
    case "UINT8": return (i) => v.getUint8(i);
    case "INT16": return (i) => v.getInt16(i * 2, true);
    case "UINT16": return (i) => v.getUint16(i * 2, true);
    case "INT32": return (i) => v.getInt32(i * 4, true);
    case "UINT32": return (i) => v.getUint32(i * 4, true);
    case "INT64": return (i) => v.getBigInt64(i * 8, true);
    case "UINT64": return (i) => v.getBigUint64(i * 8, true);
    case "FLOAT32": return (i) => v.getFloat32(i * 4, true);
    case "FLOAT64": return (i) => v.getFloat64(i * 8, true);
  }
  throw new Error(`bad component type ${type}`);
}

/** `count + 1` offsets of `type` (UINT8 to UINT64, default UINT32), checked to rise and to end within `limit`. */
function offsets(bytes: Uint8Array, type: unknown, count: number, limit: number, name: string): Float64Array {
  const kind = type === undefined ? "UINT32" : String(type);
  if (!/^UINT(8|16|32|64)$/.test(kind)) throw new Error(`property ${name} has a bad offset type`);
  const read = numbers(slice(bytes, 0, (count + 1) * BYTES[kind], name), kind);
  const out = new Float64Array(count + 1);
  for (let i = 0; i <= count; i++) {
    const at = Number(read(i));
    if (at < (i ? out[i - 1] : 0) || at > limit) throw new Error(`property ${name} has bad offsets`);
    out[i] = at;
  }
  return out;
}

const COMPONENTS: Record<string, number> = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT2: 4, MAT3: 9, MAT4: 16 };

/**
 * The features of `metadata.propertyTables[index]` by the 3D Metadata binary table format (64-bit integers
 * as bigints, enums by name), normalized, offset and scaled; `noData`, or a column the table lacks, gives the `default` or nothing.
 */
export function propertyTableProperties(metadata: StructuralMetadata, index: number): FeatureProperties {
  const t = metadata.propertyTables[index];
  if (!isObject(t)) throw new Error(`no property table ${index}`);
  const classes = isObject(metadata.schema.classes) ? metadata.schema.classes : {};
  const cls = Object.hasOwn(classes, t.class) ? classes[t.class] : undefined;
  if (!isObject(cls)) throw new Error(`no schema class ${t.class}`);
  const count = checkCount(t.count);
  const enums = isObject(metadata.schema.enums) ? metadata.schema.enums : {};
  const tableProperties = isObject(t.properties) ? t.properties : {};
  const columns: [string, Read][] = [];
  for (const [name, def] of Object.entries(isObject(cls.properties) ? cls.properties : {})) {
    if (!isObject(def)) continue;
    const p = Object.hasOwn(tableProperties, name) ? tableProperties[name] : undefined;
    if (!isObject(p)) {
      if (def.default !== undefined) columns.push([name, () => def.default]);
      continue;
    }
    columns.push([name, column(name, def, p, count, metadata.bufferViews, enums)]);
  }
  return table(count, columns);
}

function view(views: Record<number, Uint8Array>, index: unknown, name: string): Uint8Array {
  const bytes = Number.isInteger(index) ? views[index as number] : undefined;
  if (!bytes) throw new Error(`property ${name} has no buffer view ${index}`);
  return bytes;
}

const utf8 = new TextDecoder();

function column(name: string, def: Record<string, any>, p: Record<string, any>, count: number, views: Record<number, Uint8Array>, enums: Record<string, any>): Read {
  const values = view(views, p.values, name);
  const type = String(def.type);
  const variable = def.array === true && def.count === undefined;
  const fixed = def.array === true && !variable;
  if (fixed && (!Number.isInteger(def.count) || def.count < 1 || def.count > MAX_ARRAY_ELEMENTS)) throw new Error(`property ${name} has a bad count`);
  const perRow = fixed ? def.count : 1;
  const arrays = variable ? offsets(view(views, p.arrayOffsets, name), p.arrayOffsetType, count, Number.MAX_SAFE_INTEGER, name) : undefined;
  const elements = arrays ? arrays[count] : count * perRow;

  let element: (e: number) => unknown;
  let available: number;
  if (type === "STRING") {
    const strings = offsets(view(views, p.stringOffsets, name), p.stringOffsetType, elements, values.length, name);
    element = (e) => utf8.decode(values.subarray(strings[e], strings[e + 1]));
    available = elements;
  } else if (type === "BOOLEAN") {
    element = (e) => ((values[e >> 3] >> (e & 7)) & 1) === 1;
    available = values.length * 8;
  } else if (type === "ENUM") {
    const e = Object.hasOwn(enums, def.enumType) ? enums[def.enumType] : undefined;
    if (!isObject(e)) throw new Error(`property ${name} has no enum ${def.enumType}`);
    const valueType = e.valueType === undefined ? "UINT16" : String(e.valueType);
    if (!BYTES[valueType] || valueType.startsWith("FLOAT")) throw new Error(`enum ${def.enumType} has a bad value type`);
    const names = new Map<number, string>();
    for (const v of Array.isArray(e.values) ? e.values : []) if (isObject(v) && typeof v.name === "string" && !names.has(v.value)) names.set(v.value, v.name);
    const read = numbers(values, valueType);
    element = (i) => names.get(Number(read(i))) ?? "";
    available = Math.floor(values.length / BYTES[valueType]);
  } else {
    const n = COMPONENTS[type];
    const kind = String(def.componentType);
    if (!n || !BYTES[kind]) throw new Error(`property ${name} has a bad type`);
    const read = numbers(values, kind);
    element = n === 1 ? read : (e) => Array.from({ length: n }, (_, i) => read(e * n + i));
    available = Math.floor(values.length / (BYTES[kind] * n));
  }
  if (elements > available) throw new Error(`property ${name} runs past its buffer view`);

  let row: Read;
  if (arrays) {
    row = (id) => {
      const length = arrays[id + 1] - arrays[id];
      if (length > MAX_ARRAY_ELEMENTS) throw new Error(`property ${name} has too long an array`);
      return Array.from({ length }, (_, i) => element(arrays[id] + i));
    };
  } else {
    row = fixed ? (id) => Array.from({ length: perRow }, (_, i) => element(id * perRow + i)) : element;
  }
  const transform = transformer(def, p, type, variable);
  const noData = def.noData;
  return (id) => {
    const raw = row(id);
    if (noData !== undefined && same(raw, noData)) return def.default;
    return transform ? transform(raw) : raw;
  };
}

/**
 * Normalization of integer components, then `offset + scale * value` component-wise (the table
 * property's over the class's; fixed-size values only); null when nothing applies.
 */
function transformer(def: Record<string, any>, p: Record<string, any>, type: string, variable: boolean): ((v: unknown) => unknown) | null {
  if (!COMPONENTS[type]) return null;
  const max = INT_MAX[def.componentType];
  const normalize = def.normalized === true && max !== undefined;
  const float = def.componentType === "FLOAT32" || def.componentType === "FLOAT64";
  const offset = p.offset ?? def.offset;
  const scale = p.scale ?? def.scale;
  const shift = !variable && (float || normalize) && (offset !== undefined || scale !== undefined);
  if (!normalize && !shift) return null;
  const apply = (v: unknown, o: unknown, s: unknown): unknown => {
    if (Array.isArray(v)) return v.map((x, i) => apply(x, Array.isArray(o) ? o[i] : o, Array.isArray(s) ? s[i] : s));
    const x = normalize ? Math.max(Number(v) / max, -1) : (v as number);
    return shift ? (typeof o === "number" ? o : 0) + (typeof s === "number" ? s : 1) * x : x;
  };
  return (v) => apply(v, offset, scale);
}

function same(a: unknown, b: unknown): boolean {
  if (Array.isArray(a)) return Array.isArray(b) && a.length === b.length && a.every((x, i) => same(x, b[i]));
  if (typeof a === "bigint") return (typeof b === "number" && Number.isInteger(b)) || typeof b === "bigint" ? a === BigInt(b) : false;
  return a === b;
}

/** The feature ID of `vertex` in `ids`, or undefined for its null feature ID. */
export function featureId(ids: FeatureIds, vertex: number): number | undefined {
  const id = ids.attribute ? ids.attribute.data[vertex] : ids.implicit ? ids.implicit.offset + Math.floor(vertex / ids.implicit.repeat) : undefined;
  return id === undefined || id === ids.nullFeatureId ? undefined : id;
}
