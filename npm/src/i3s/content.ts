// I3S 1.7 and 1.8 node contents for mbmap/3d as @loaders.gl/i3s 4.5.4 (MIT) reads them: geometry buffers
// (uncompressed, or Draco with its I3S metadata) as one primitive around the node's center, its resources,
// material and attribute buffers. Import-free but for sibling modules.

import type { Attribute, DracoDecode, Material, Primitive } from "../model/gltf.ts";
import { eastNorthUp } from "../tiles/geo.ts";

/** Caps on a node: geometry and texture bytes, vertices, features, and values in an attribute buffer. */
export const MAX_I3S_BYTES = 256 << 20;
export const MAX_I3S_TEXTURE_BYTES = 64 << 20;
export const MAX_I3S_VERTICES = 1 << 24;
export const MAX_I3S_FEATURES = 1 << 22;
export const MAX_I3S_VALUES = 1 << 24;

const RADII_SQUARED = [6378137.0 ** 2, 6378137.0 ** 2, 6356752.3142451793 ** 2];
const DEGREES_TO_RADIANS = (1 / 180) * Math.PI;

/** ECEF meters of degrees and a height, operation for operation as math.gl's `cartographicToCartesian` (geo.ts's differs in the last bit). */
export function cartesian(lngDeg: number, latDeg: number, height: number): [number, number, number] {
  const lng = lngDeg * DEGREES_TO_RADIANS;
  const lat = latDeg * DEGREES_TO_RADIANS;
  const cosLat = Math.cos(lat);
  let [x, y, z] = [cosLat * Math.cos(lng), cosLat * Math.sin(lng), Math.sin(lat)];
  const len = Math.sqrt(x * x + y * y + z * z);
  if (len !== 0) [x, y, z] = [x / len, y / len, z / len];
  const k = [RADII_SQUARED[0] * x, RADII_SQUARED[1] * y, RADII_SQUARED[2] * z];
  const inverse = 1 / Math.sqrt(x * k[0] + y * k[1] + z * k[2]);
  return [k[0] * inverse + x * height, k[1] * inverse + y * height, k[2] * inverse + z * height];
}

/** The parts of a scene layer's JSON that node contents need. */
export interface I3sLayer {
  spatialReference?: { wkid?: number; latestWkid?: number };
  store?: { normalReferenceFrame?: string };
  geometryDefinitions?: { geometryBuffers?: Record<string, any>[] }[];
  materialDefinitions?: Record<string, any>[];
  textureSetDefinitions?: { atlas?: boolean; formats?: { name: string; format: string }[] }[];
  attributeStorageInfo?: I3sAttributeInfo[];
}

/** A node of a node page: `obb` (center in degrees and meters), `mesh` with its resources and definitions. */
export interface I3sNode {
  obb?: { center: number[] };
  mbs?: number[];
  mesh?: {
    geometry?: { definition: number; resource: number; vertexCount?: number; featureCount?: number };
    material?: { definition: number; resource: number };
    attribute?: { resource: number };
  };
}

/** A node's content: `center` [lng, lat, h] the primitive's positions are relative to, `featureIds` per feature index (strings past 2^53). */
export interface I3sGeometry {
  center: [number, number, number];
  primitive: Primitive;
  featureIds: Float64Array | string[];
  count: number;
}

/** A layer's spatial reference must be WGS 84 (4326), the only one loaders.gl reads. */
export function checkSpatialReference(layer: I3sLayer): void {
  const sr = layer.spatialReference;
  if (sr?.wkid !== 4326 && sr?.latestWkid !== 4326) throw new Error(`I3S: spatial reference ${sr?.latestWkid ?? sr?.wkid ?? "none"} is not supported (only 4326)`);
}

/** A node's center: its oriented box's, else its bounding sphere's, as loaders.gl's `mbs`. */
export function nodeCenter(node: I3sNode): [number, number, number] {
  const c = node.obb?.center ?? node.mbs;
  if (!Array.isArray(c) || c.length < 3 || !c.slice(0, 3).every((v) => typeof v === "number" && Number.isFinite(v))) throw new Error("I3S: the node has no center");
  return [c[0], c[1], c[2]];
}

const isDraco = (b: Record<string, any> | undefined) => b?.compressedAttributes?.encoding === "draco";

/** The geometry buffer to read of a definition: the Draco one when offered (as loaders.gl with `useDracoGeometry`), else an uncompressed one. */
export function geometryBufferOf(layer: I3sLayer, definition: number): { index: number; draco: boolean } | undefined {
  const buffers = layer.geometryDefinitions?.[definition]?.geometryBuffers ?? [];
  let index = buffers.findIndex(isDraco);
  if (index < 0) index = buffers.findIndex((b) => !b?.compressedAttributes);
  return index < 0 ? undefined : { index, draco: isDraco(buffers[index]) };
}

/** The JPEG or PNG texture of a material definition: the format's resource name and whether it is an atlas (with uv regions). */
export function textureOf(layer: I3sLayer, materialDefinition: number): { name: string; format: string; atlas: boolean } | undefined {
  const set = layer.materialDefinitions?.[materialDefinition]?.pbrMetallicRoughness?.baseColorTexture?.textureSetDefinitionId;
  const def = typeof set === "number" ? layer.textureSetDefinitions?.[set] : undefined;
  const format = def?.formats?.find((f) => f.format === "jpg") ?? def?.formats?.find((f) => f.format === "png");
  return format && typeof format.name === "string" ? { name: format.name, format: format.format, atlas: def?.atlas === true } : undefined;
}

/** A node's resources as paths relative to the layer (its REST URL): geometry, texture and attribute buffers by `attributeStorageInfo`. */
export function nodeResources(layer: I3sLayer, node: I3sNode): { geometry?: string; buffer?: number; texture?: string; attributes: string[] } | undefined {
  const mesh = node.mesh;
  if (!mesh?.geometry) return undefined;
  const chosen = geometryBufferOf(layer, mesh.geometry.definition);
  const texture = mesh.material && textureOf(layer, mesh.material.definition);
  const a = mesh.attribute?.resource;
  return {
    geometry: chosen && `nodes/${mesh.geometry.resource}/geometries/${chosen.index}`,
    buffer: chosen?.index,
    texture: texture && mesh.material && `nodes/${mesh.material.resource}/textures/${texture.name}`,
    attributes: a === undefined ? [] : (layer.attributeStorageInfo ?? []).map((info) => `nodes/${a}/attributes/${info.key}/0`),
  };
}

/** A material definition as mbmap draws it (I3S colors are 0 to 1, alpha modes lowercase; alphaCutoff 0.25 by default as loaders.gl). */
export function materialOf(layer: I3sLayer, definition: number | undefined, textured: boolean): Material {
  const md = (definition === undefined ? undefined : layer.materialDefinitions?.[definition]) ?? {};
  const f = md.pbrMetallicRoughness?.baseColorFactor;
  const color: [number, number, number, number] = Array.isArray(f) && f.length === 4 && f.every((v: unknown) => typeof v === "number") ? [f[0], f[1], f[2], f[3]] : [1, 1, 1, 1];
  const mode = String(md.alphaMode ?? "opaque").toUpperCase();
  return {
    color,
    texture: textured ? { image: 0, wrapS: 10497, wrapT: 10497, minFilter: 9987, magFilter: 9729, texCoord: 0 } : undefined,
    alphaMode: mode === "MASK" || mode === "BLEND" ? mode : "OPAQUE",
    alphaCutoff: typeof md.alphaCutoff === "number" && md.alphaCutoff > 0 ? md.alphaCutoff : 0.25,
    doubleSided: md.doubleSided === true || md.cullFace === "none",
    unlit: false,
  };
}

/** Byte sizes of I3S value types. */
const SIZES: Record<string, number> = { Int8: 1, UInt8: 1, Int16: 2, UInt16: 2, Int32: 4, UInt32: 4, Oid32: 4, Float32: 4, Int64: 8, UInt64: 8, Oid64: 8, Float64: 8 };

/** The uncompressed buffer's vertex and feature attributes in the order they are stored, with the types read. */
const VERTEX_LAYOUT: [string, string, number[]][] = [
  ["position", "Float32", [3]],
  ["normal", "Float32", [3]],
  ["uv0", "Float32", [2]],
  ["color", "UInt8", [3, 4]],
  ["uvRegion", "UInt16", [4]],
];
const FEATURE_LAYOUT: [string, string, number[]][] = [
  ["featureId", "UInt64", [1]],
  ["faceRange", "UInt32", [2]],
];

/** The attributes read from a buffer, by I3S name, before positions are placed. */
interface Raw {
  vertexCount: number;
  position: Float32Array;
  normal?: Float32Array;
  uv0?: Float32Array;
  color?: { data: Uint8Array; size: number };
  uvRegion?: Uint16Array;
  indices?: Uint32Array;
  featureIndex: Float32Array;
  featureIds: Float64Array | string[];
  scale: [number, number];
}

function copy(bytes: Uint8Array, at: number, length: number): ArrayBuffer {
  return bytes.slice(at, at + length).buffer;
}

/** UInt64 values as numbers, or all as decimal strings when one passes 2^53. */
function ids64(lo: Uint32Array, hi: Uint32Array): Float64Array | string[] {
  if (hi.every((h) => h < 1 << 21)) return Float64Array.from(lo, (l, i) => l + hi[i] * 2 ** 32);
  return Array.from(lo, (l, i) => ((BigInt(hi[i]) << 32n) | BigInt(l)).toString());
}

/** The uncompressed layout: a header (vertex and feature counts when `offset` is 8 or more), then each declared attribute in turn. */
function readUncompressed(bytes: Uint8Array, def: Record<string, any>, node: I3sNode): Raw {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const offset = Number.isInteger(def.offset) && def.offset >= 0 ? def.offset : 0;
  if (bytes.length < offset) throw new Error("I3S: the geometry buffer is shorter than its header");
  const vertexCount = offset >= 8 ? view.getUint32(0, true) : node.mesh?.geometry?.vertexCount;
  const featureCount = offset >= 8 ? view.getUint32(4, true) : node.mesh?.geometry?.featureCount;
  if (!Number.isInteger(vertexCount) || vertexCount! > MAX_I3S_VERTICES || vertexCount! % 3 !== 0) throw new Error("I3S: bad vertex count");
  if (!Number.isInteger(featureCount) || featureCount! > MAX_I3S_FEATURES) throw new Error("I3S: bad feature count");
  const n = vertexCount!;
  const f = featureCount!;
  let at = offset;
  const read: Record<string, ArrayBuffer> = {};
  const sizes: Record<string, number> = {};
  for (const [layout, count] of [[VERTEX_LAYOUT, n], [FEATURE_LAYOUT, f]] as const) {
    for (const [name, type, components] of layout) {
      const a = def[name];
      if (a === undefined) continue;
      if (a?.type !== type || !components.includes(a.component)) throw new Error(`I3S: ${name} as ${a?.type} x ${a?.component} is not supported`);
      const length = count * a.component * SIZES[type];
      if (at + length > bytes.length) throw new Error(`I3S: ${name} runs past the geometry buffer`);
      read[name] = copy(bytes, at, length);
      sizes[name] = a.component;
      at += length;
    }
  }
  if (!read.position) throw new Error("I3S: the geometry buffer has no positions");
  const featureIndex = new Float32Array(n).fill(-1);
  let featureIds: Float64Array | string[] = new Float64Array(0);
  if (read.featureId && read.faceRange) {
    const words = new Uint32Array(read.featureId);
    featureIds = ids64(words.filter((_, i) => i % 2 === 0), words.filter((_, i) => i % 2 === 1));
    const ranges = new Uint32Array(read.faceRange);
    for (let i = 0; i < f; i++) {
      const [first, last] = [ranges[i * 2], ranges[i * 2 + 1]];
      if (first > last || last >= n / 3) throw new Error("I3S: a face range runs past the vertices");
      featureIndex.fill(i, first * 3, last * 3 + 3);
    }
  }
  return {
    vertexCount: n,
    position: new Float32Array(read.position),
    normal: read.normal && new Float32Array(read.normal),
    uv0: read.uv0 && new Float32Array(read.uv0),
    color: read.color && { data: new Uint8Array(read.color), size: sizes.color },
    uvRegion: read.uvRegion && new Uint16Array(read.uvRegion),
    featureIndex,
    featureIds,
    scale: [1, 1],
  };
}

/** A Draco metadata entry's raw bytes, read as loaders.gl's DracoParser reads them (`string`, `double`, `intArray`). */
const entryString = (b: Uint8Array | undefined) => (b ? new TextDecoder().decode(b) : undefined);
const entryDouble = (b: Uint8Array | undefined) => (b && b.length >= 8 ? new DataView(b.buffer, b.byteOffset, 8).getFloat64(0, true) : undefined);
const entryInts = (b: Uint8Array | undefined) => (b ? new Int32Array(copy(b, 0, b.length - (b.length % 4))) : undefined);

/**
 * The top-level entries of each attribute's metadata in a Draco bitstream, by attribute unique id (Draco's
 * `MetadataDecoder::DecodeGeometryMetadata`; sub-metadata skipped). Malformed metadata gives what was read.
 */
export function dracoMetadata(bytes: Uint8Array): Map<number, Map<string, Uint8Array>> {
  const out = new Map<number, Map<string, Uint8Array>>();
  if (bytes.length < 11 || new TextDecoder().decode(bytes.subarray(0, 5)) !== "DRACO" || bytes[5] < 2) return out;
  if (((bytes[9] | (bytes[10] << 8)) & 0x8000) === 0) return out;
  let at = 11;
  const varint = () => {
    let v = 0;
    for (let shift = 0; shift < 35; shift += 7) {
      if (at >= bytes.length) throw new Error("end");
      const b = bytes[at++];
      v += (b & 0x7f) * 2 ** shift;
      if (b < 0x80) return v;
    }
    throw new Error("varint");
  };
  const take = (n: number) => {
    if (at + n > bytes.length) throw new Error("end");
    at += n;
    return bytes.subarray(at - n, at);
  };
  const name = () => new TextDecoder().decode(take(take(1)[0]));
  const entries = () => {
    const e = new Map<string, Uint8Array>();
    for (let i = varint(); i > 0; i--) {
      const key = name();
      e.set(key, take(varint()));
    }
    return e;
  };
  const tree = () => {
    const top = entries();
    for (let pending = varint(); pending > 0; pending--) {
      if (pending > bytes.length) throw new Error("subs");
      name();
      entries();
      pending += varint();
    }
    return top;
  };
  try {
    for (let i = varint(); i > 0; i--) {
      const id = varint();
      out.set(id, tree());
    }
  } catch {
    // The wasm decoder refuses what is malformed; the entries read so far are kept.
  }
  return out;
}

/** The I3S names of Draco's attribute types (POSITION, NORMAL, COLOR, TEX_COORD); GENERIC ones are named by their metadata. */
const DRACO_NAMES = ["position", "normal", "color", "uv0"];

/** The Draco layout: attributes named by type or `i3s-attribute-type` metadata, which also holds feature ids and position scales. */
function readDraco(bytes: Uint8Array, decode: DracoDecode): Raw {
  const mesh = decode(bytes);
  const metadata = dracoMetadata(bytes);
  const byName = new Map<string, { attribute: Attribute; meta: Map<string, Uint8Array> }>();
  for (const [id, attribute] of mesh.attributes) {
    const meta = metadata.get(id) ?? new Map();
    const name = entryString(meta.get("i3s-attribute-type")) ?? DRACO_NAMES[attribute.dracoType ?? -1];
    if (name !== undefined && !byName.has(name)) byName.set(name, { attribute, meta });
  }
  const position = byName.get("position");
  if (!position || !(position.attribute.data instanceof Float32Array) || position.attribute.size !== 3) throw new Error("I3S: the Draco geometry has no float positions");
  const n = position.attribute.data.length / 3;
  if (n > MAX_I3S_VERTICES) throw new Error("I3S: too many vertices");
  for (const i of mesh.indices) if (i >= n) throw new Error("I3S: a Draco index is past the vertices");
  const floats = (name: string, size: number) => {
    const a = byName.get(name)?.attribute;
    if (!a) return undefined;
    if (!(a.data instanceof Float32Array) || a.size !== size) throw new Error(`I3S: Draco ${name} is not float x ${size}`);
    return a.data;
  };
  const color = byName.get("color")?.attribute;
  if (color && (!(color.data instanceof Uint8Array) || (color.size !== 3 && color.size !== 4))) throw new Error("I3S: Draco colors are not UInt8 x 3 or 4");
  const region = byName.get("uv-region")?.attribute;
  if (region && (!(region.data instanceof Uint16Array) || region.size !== 4)) throw new Error("I3S: Draco uv regions are not UInt16 x 4");
  const fi = byName.get("feature-index");
  const featureIds = Float64Array.from(entryInts(fi?.meta.get("i3s-feature-ids")) ?? []);
  if (featureIds.length > MAX_I3S_FEATURES) throw new Error("I3S: too many features");
  const featureIndex = new Float32Array(n).fill(-1);
  if (fi) {
    if (fi.attribute.size !== 1 || fi.attribute.data.length !== n) throw new Error("I3S: Draco feature indices are not one per vertex");
    for (let v = 0; v < n; v++) {
      const k = fi.attribute.data[v];
      if (k >= featureIds.length) throw new Error("I3S: a Draco feature index is past the feature ids");
      featureIndex[v] = k;
    }
  }
  const scale = (key: string) => entryDouble(position.meta.get(key)) || 1;
  return {
    vertexCount: n,
    position: position.attribute.data,
    normal: floats("normal", 3),
    uv0: floats("uv0", 2),
    color: color && { data: color.data as Uint8Array, size: color.size },
    uvRegion: region?.data as Uint16Array | undefined,
    indices: mesh.indices,
    featureIndex,
    featureIds,
    scale: [scale("i3s-scale_x"), scale("i3s-scale_y")],
  };
}

/**
 * A node's geometry buffer (`buffer` indexes its definition's `geometryBuffers`) as one triangle primitive of material 0;
 * attributes are listed in docs/FORMATS.md "Model worker messages" (`op: "i3s"`).
 */
export function readI3sGeometry(bytes: Uint8Array, layer: I3sLayer, node: I3sNode, buffer: number, draco?: DracoDecode): I3sGeometry {
  checkSpatialReference(layer);
  const center = nodeCenter(node);
  const definition = node.mesh?.geometry?.definition;
  const def = definition === undefined ? undefined : layer.geometryDefinitions?.[definition]?.geometryBuffers?.[buffer];
  if (!def) throw new Error("I3S: the node's geometry buffer is not defined");
  let raw: Raw;
  if (isDraco(def)) {
    if (!draco) throw new Error("I3S: no Draco decoder");
    raw = readDraco(bytes, draco);
  } else if (def.compressedAttributes) {
    throw new Error(`I3S: ${def.compressedAttributes.encoding} geometry is not supported`);
  } else {
    raw = readUncompressed(bytes, def, node);
  }
  const origin = cartesian(center[0], center[1], center[2]);
  const m = eastNorthUp(origin);
  const n = raw.vertexCount;
  const positions = new Float32Array(n * 3);
  const [sx, sy] = raw.scale;
  for (let i = 0; i < n * 3; i += 3) {
    const p = cartesian(raw.position[i] * sx + center[0], raw.position[i + 1] * sy + center[1], raw.position[i + 2] + center[2]);
    const [dx, dy, dz] = [p[0] - origin[0], p[1] - origin[1], p[2] - origin[2]];
    positions[i] = m[0] * dx + m[1] * dy + m[2] * dz;
    positions[i + 1] = m[4] * dx + m[5] * dy + m[6] * dz;
    positions[i + 2] = m[8] * dx + m[9] * dy + m[10] * dz;
  }
  const attributes: Record<string, Attribute> = {
    POSITION: { data: positions, size: 3, type: 5126, normalized: false },
    _BATCHID: { data: raw.featureIndex, size: 1, type: 5126, normalized: false },
  };
  if (raw.normal) {
    let normals = raw.normal;
    if ((layer.store?.normalReferenceFrame ?? "earth-centered") === "earth-centered") {
      normals = new Float32Array(raw.normal.length);
      for (let i = 0; i < normals.length; i += 3) {
        const [x, y, z] = [raw.normal[i], raw.normal[i + 1], raw.normal[i + 2]];
        normals[i] = m[0] * x + m[1] * y + m[2] * z;
        normals[i + 1] = m[4] * x + m[5] * y + m[6] * z;
        normals[i + 2] = m[8] * x + m[9] * y + m[10] * z;
      }
    }
    attributes.NORMAL = { data: normals, size: 3, type: 5126, normalized: false };
  }
  if (raw.uv0) attributes.TEXCOORD_0 = { data: raw.uv0, size: 2, type: 5126, normalized: false };
  if (raw.color) attributes.COLOR_0 = { data: raw.color.data, size: raw.color.size, type: 5121, normalized: true };
  if (raw.uvRegion) attributes._UV_REGION = { data: raw.uvRegion, size: 4, type: 5123, normalized: true };
  const primitive: Primitive = {
    attributes,
    indices: raw.indices,
    mode: 4,
    material: 0,
    matrix: new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
  };
  return { center, primitive, featureIds: raw.featureIds, count: n };
}

/** One field of a layer's `attributeStorageInfo`. */
export interface I3sAttributeInfo {
  key: string;
  name: string;
  header?: { property: string; valueType: string }[];
  ordering?: string[];
  attributeValues?: { valueType: string; valuesPerElement?: number };
  attributeByteCounts?: { valueType: string; valuesPerElement?: number };
  objectIds?: { valueType: string; valuesPerElement?: number };
}

export type I3sValues = string[] | Int8Array | Uint8Array | Int16Array | Uint16Array | Int32Array | Uint32Array | Float32Array | Float64Array | BigInt64Array | BigUint64Array;

const TYPED: Record<string, any> = {
  Int8: Int8Array, UInt8: Uint8Array, Int16: Int16Array, UInt16: Uint16Array, Int32: Int32Array, UInt32: Uint32Array, Oid32: Uint32Array,
  Float32: Float32Array, Float64: Float64Array, Int64: BigInt64Array, UInt64: BigUint64Array, Oid64: BigUint64Array,
};

/**
 * An attribute buffer's values, one per feature of the node: the header's fields (`count` first), then
 * each array of `ordering`, every array starting at a multiple of its value size. Strings are UTF-8 with
 * their byte counts, a trailing NUL dropped (loaders.gl keeps it).
 */
export function readI3sAttribute(bytes: Uint8Array, info: I3sAttributeInfo): I3sValues {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const header = info.header ?? [{ property: "count", valueType: "UInt32" }];
  let at = 0;
  const fields: Record<string, number> = {};
  for (const h of header) {
    const size = SIZES[h.valueType];
    if (size !== 4 || at + 4 > bytes.length) throw new Error(`I3S attribute ${info.name}: bad header`);
    fields[h.property] = view.getUint32(at, true);
    at += 4;
  }
  const count = fields.count;
  if (count === undefined || count > MAX_I3S_VALUES) throw new Error(`I3S attribute ${info.name}: bad count`);
  const arrays: Record<string, any> = { attributeValues: info.attributeValues, attributeByteCounts: info.attributeByteCounts, ObjectIds: info.objectIds, objectIds: info.objectIds };
  const ordering = info.ordering ?? [info.objectIds ? "ObjectIds" : "attributeValues"];
  let byteCounts: Uint32Array | undefined;
  for (const key of ordering) {
    const a = arrays[key];
    if (!a) throw new Error(`I3S attribute ${info.name}: no ${key}`);
    if ((a.valuesPerElement ?? 1) !== 1) throw new Error(`I3S attribute ${info.name}: ${a.valuesPerElement} values per element`);
    if (a.valueType === "String") {
      if (!byteCounts) throw new Error(`I3S attribute ${info.name}: strings without byte counts`);
      const decoder = new TextDecoder();
      const out: string[] = [];
      for (const n of byteCounts) {
        if (at + n > bytes.length) throw new Error(`I3S attribute ${info.name}: strings run past the buffer`);
        const s = decoder.decode(bytes.subarray(at, at + n));
        out.push(s.endsWith("\0") ? s.slice(0, -1) : s);
        at += n;
      }
      return out;
    }
    const Typed = TYPED[a.valueType];
    if (!Typed) throw new Error(`I3S attribute ${info.name}: unknown type ${a.valueType}`);
    const size = SIZES[a.valueType];
    at = Math.ceil(at / size) * size;
    if (at + count * size > bytes.length) throw new Error(`I3S attribute ${info.name}: values run past the buffer`);
    const values = new Typed(copy(bytes, at, count * size));
    at += count * size;
    if (key === "attributeByteCounts") byteCounts = values;
    else return values;
  }
  throw new Error(`I3S attribute ${info.name}: no values`);
}
