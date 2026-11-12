// A 3D tile's content for mbmap/3d: Batched 3D Model (b3dm), Instanced 3D Model (i3dm), Point Cloud
// (pnts), Composite (cmpt) of those, or a glTF itself (3D Tiles 1.1).
import { readGltf, type Attribute, type DracoDecode, type Material, type MeshoptDecode, type Model } from "../model/gltf.ts";
import { cross, eastNorthUp, normalize, type Vec3 } from "./geo.ts";

const B3DM = 0x6d643362;
const I3DM = 0x6d643369;
const CMPT = 0x74706d63;
const PNTS = 0x73746e70;
const GLB = 0x46546c67;
const B3DM_HEADER_BYTES = 28;
const PNTS_HEADER_BYTES = 28;
const I3DM_HEADER_BYTES = 32;
const CMPT_HEADER_BYTES = 16;
const INNER_HEADER_BYTES = 12;
export const MAX_INSTANCES = 1_000_000;
export const MAX_COMPOSITE_TILES = 65536;
export const MAX_COMPOSITE_DEPTH = 8;
export const MAX_POINTS = 10_000_000;

/**
 * An i3dm's instances: `matrices` (16 f64 per instance, column-major) take the model, its glTF +Y up
 * already turned to +Z up, to tile coordinates, RTC_CENTER included; `batchIds` (BATCH_ID, else the
 * instance's index) index the batch table.
 */
export interface Instances {
  matrices: Float64Array;
  batchIds: Uint32Array;
}

/**
 * A tile's model with `rtc` (RTC_CENTER or CESIUM_RTC, plus a pnts' QUANTIZED_VOLUME_OFFSET; null for i3dm),
 * its batch and an i3dm's `instances`. A pnts' model is one POINTS primitive in tile coordinates (+Z up,
 * unlike glTF). A cmpt has an empty model and its inner contents in `parts` (nested cmpts flattened).
 */
export interface TileContent {
  kind: "b3dm" | "i3dm" | "pnts" | "cmpt" | "glTF";
  model: Model;
  rtc: [number, number, number] | null;
  batchLength: number;
  batchTable: Record<string, unknown> | null;
  batchBinary: Uint8Array;
  instances: Instances | null;
  parts: TileContent[];
}

type Json = Record<string, any>;

function json(bytes: Uint8Array, what: string): Json {
  if (!bytes.length) return {};
  const value = JSON.parse(new TextDecoder().decode(bytes));
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`the ${what} is not a JSON object`);
  return value;
}

const viewOf = (bytes: Uint8Array) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

interface Tables {
  featureTable: Json;
  featureBinary: Uint8Array;
  batchTable: Json | null;
  batchBinary: Uint8Array;
  body: Uint8Array;
}

/** The feature and batch tables of a b3dm or i3dm whose header ends at `header`, and the body after them. */
function readTables(bytes: Uint8Array, name: string, header: number): Tables {
  const view = viewOf(bytes);
  if (bytes.length < header) throw new Error(`the ${name} header is cut short`);
  if (view.getUint32(4, true) !== 1) throw new Error(`only ${name} version 1 is read`);
  const length = view.getUint32(8, true);
  if (length > bytes.length) throw new Error(`the ${name} is cut short`);
  const [ftJson, ftBin, btJson, btBin] = [12, 16, 20, 24].map((at) => view.getUint32(at, true));
  // Older b3dm (a batch length where the feature table length is now) would read as huge lengths.
  const bodyAt = header + ftJson + ftBin + btJson + btBin;
  if (bodyAt > length) throw new Error(`the ${name}'s tables run past the file`);
  const ftBinAt = header + ftJson;
  const btAt = ftBinAt + ftBin;
  return {
    featureTable: json(bytes.subarray(header, ftBinAt), `${name} feature table`),
    featureBinary: bytes.subarray(ftBinAt, btAt),
    batchTable: btJson ? json(bytes.subarray(btAt, btAt + btJson), `${name} batch table`) : null,
    batchBinary: bytes.subarray(btAt + btJson, bodyAt),
    body: bytes.subarray(bodyAt, length),
  };
}

const COMPONENTS: Record<string, [number, (v: DataView, at: number) => number, new (a: number[]) => ArrayLike<number>]> = {
  BYTE: [1, (v, at) => v.getInt8(at), Int8Array],
  UNSIGNED_BYTE: [1, (v, at) => v.getUint8(at), Uint8Array],
  SHORT: [2, (v, at) => v.getInt16(at, true), Int16Array],
  UNSIGNED_SHORT: [2, (v, at) => v.getUint16(at, true), Uint16Array],
  INT: [4, (v, at) => v.getInt32(at, true), Int32Array],
  UNSIGNED_INT: [4, (v, at) => v.getUint32(at, true), Uint32Array],
  FLOAT: [4, (v, at) => v.getFloat32(at, true), Float32Array],
  DOUBLE: [8, (v, at) => v.getFloat64(at, true), Float64Array],
};

/** A global semantic of `n` floats: a JSON array, or a reference into the binary body (float32). */
function globalFloats(ft: Json, bin: Uint8Array, name: string, n: number): number[] | null {
  const value = ft[name];
  if (Array.isArray(value)) {
    if (value.length !== n || !value.every(Number.isFinite)) throw new Error(`${name} is not ${n} numbers`);
    return value;
  }
  if (!value) return null;
  const at = value.byteOffset;
  if (!Number.isInteger(at) || at < 0 || at + 4 * n > bin.length) throw new Error(`${name} runs past the feature table`);
  const v = viewOf(bin);
  return Array.from({ length: n }, (_, i) => v.getFloat32(at + 4 * i, true));
}

/** A per-instance semantic as numbers (`count` × `n`), its component type from the JSON (as loaders.gl), or null when absent. */
function perInstance(ft: Json, bin: Uint8Array, name: string, type: string, n: number, count: number): ArrayLike<number> | null {
  const value = ft[name];
  if (!value) return null;
  const typeName = typeof value.componentType === "string" ? value.componentType : type;
  const component = Object.hasOwn(COMPONENTS, typeName) ? COMPONENTS[typeName] : undefined;
  if (!component) throw new Error(`${name} has an unknown componentType`);
  const [size, read, Typed] = component;
  if (Array.isArray(value)) {
    if (value.length < count * n) throw new Error(`${name} has too few values`);
    return new Typed(value);
  }
  const at = value.byteOffset;
  if (!Number.isInteger(at) || at < 0 || at + size * n * count > bin.length) throw new Error(`${name} runs past the feature table`);
  const v = viewOf(bin);
  const out = new Float64Array(count * n);
  for (let i = 0; i < out.length; i++) out[i] = read(v, at + size * i);
  return out;
}

/** AttributeCompression.octDecodeInRange(x, y, range) of Cesium, as @loaders.gl/math has it. */
function octDecode(x: number, y: number, range = 65535): Vec3 {
  let vx = (x / range) * 2 - 1;
  let vy = (y / range) * 2 - 1;
  const vz = 1 - (Math.abs(vx) + Math.abs(vy));
  if (vz < 0) {
    const old = vx;
    vx = (1 - Math.abs(vy)) * (old < 0 ? -1 : 1);
    vy = (1 - Math.abs(old)) * (vy < 0 ? -1 : 1);
  }
  return normalize([vx, vy, vz]);
}

/** The column-major 3x3 rotation to its quaternion and back as math.gl's `fromMatrix3` and `fromQuaternion` do. */
function roundTrip(m: ArrayLike<number>): number[] {
  const q = [0, 0, 0, 0];
  const trace = m[0] + m[4] + m[8];
  if (trace > 0) {
    let root = Math.sqrt(trace + 1);
    q[3] = 0.5 * root;
    root = 0.5 / root;
    q[0] = (m[5] - m[7]) * root;
    q[1] = (m[6] - m[2]) * root;
    q[2] = (m[1] - m[3]) * root;
  } else {
    let i = 0;
    if (m[4] > m[0]) i = 1;
    if (m[8] > m[i * 3 + i]) i = 2;
    const j = (i + 1) % 3;
    const k = (i + 2) % 3;
    let root = Math.sqrt(m[i * 3 + i] - m[j * 3 + j] - m[k * 3 + k] + 1);
    q[i] = 0.5 * root;
    root = 0.5 / root;
    q[3] = (m[j * 3 + k] - m[k * 3 + j]) * root;
    q[j] = (m[j * 3 + i] + m[i * 3 + j]) * root;
    q[k] = (m[k * 3 + i] + m[i * 3 + k]) * root;
  }
  const [x, y, z, w] = q;
  const [x2, y2, z2] = [x + x, y + y, z + z];
  const [xx, yx, yy, zx, zy, zz, wx, wy, wz] = [x * x2, y * x2, y * y2, z * x2, z * y2, z * z2, w * x2, w * y2, w * z2];
  return [1 - yy - zz, yx + wz, zx - wy, yx - wz, 1 - xx - zz, zy + wx, zx + wy, zy - wx, 1 - xx - yy];
}

/** The east-north-up rotation at `p` as loaders.gl takes it from math.gl (`getRotationMatrix3`, its scales by row). */
function enuRotation(p: Vec3): number[] {
  const m = eastNorthUp(p);
  const s = [0, 4, 8].map((c) => 1 / Math.sqrt(m[c] * m[c] + m[c + 1] * m[c + 1] + m[c + 2] * m[c + 2]));
  return [m[0] * s[0], m[1] * s[1], m[2] * s[2], m[4] * s[0], m[5] * s[1], m[6] * s[2], m[8] * s[0], m[9] * s[1], m[10] * s[2]];
}

/** The instances of an i3dm's feature table: translation × rotation × scale as loaders.gl builds them, plus RTC_CENTER. */
function readInstances(ft: Json, bin: Uint8Array): Instances {
  const n = ft.INSTANCES_LENGTH;
  if (!Number.isInteger(n) || n < 0) throw new Error("the i3dm has no INSTANCES_LENGTH");
  if (n > MAX_INSTANCES) throw new Error(`the i3dm has more than ${MAX_INSTANCES} instances`);
  const rtc = globalFloats(ft, bin, "RTC_CENTER", 3) ?? [0, 0, 0];
  let positions = perInstance(ft, bin, "POSITION", "FLOAT", 3, n);
  if (!positions) {
    const quantized = perInstance(ft, bin, "POSITION_QUANTIZED", "UNSIGNED_SHORT", 3, n);
    if (!quantized) throw new Error("the i3dm has neither POSITION nor POSITION_QUANTIZED");
    const offset = globalFloats(ft, bin, "QUANTIZED_VOLUME_OFFSET", 3);
    const scale = globalFloats(ft, bin, "QUANTIZED_VOLUME_SCALE", 3);
    if (!offset || !scale) throw new Error("POSITION_QUANTIZED needs QUANTIZED_VOLUME_OFFSET and QUANTIZED_VOLUME_SCALE");
    positions = Float64Array.from(quantized, (q, i) => (q / 65535) * scale[i % 3] + offset[i % 3]);
  }
  const up = perInstance(ft, bin, "NORMAL_UP", "FLOAT", 3, n);
  const right = perInstance(ft, bin, "NORMAL_RIGHT", "FLOAT", 3, n);
  if (!up !== !right) throw new Error("NORMAL_UP and NORMAL_RIGHT go together");
  const octUp = up ? null : perInstance(ft, bin, "NORMAL_UP_OCT32P", "UNSIGNED_SHORT", 2, n);
  const octRight = up ? null : perInstance(ft, bin, "NORMAL_RIGHT_OCT32P", "UNSIGNED_SHORT", 2, n);
  if (!octUp !== !octRight) throw new Error("NORMAL_UP_OCT32P and NORMAL_RIGHT_OCT32P go together");
  const enu = !up && !octUp && Boolean(ft.EAST_NORTH_UP);
  const scales = perInstance(ft, bin, "SCALE", "FLOAT", 1, n);
  const nonUniform = perInstance(ft, bin, "SCALE_NON_UNIFORM", "FLOAT", 3, n);
  const ids = perInstance(ft, bin, "BATCH_ID", "UNSIGNED_SHORT", 1, n);
  const matrices = new Float64Array(16 * n);
  const batchIds = new Uint32Array(n);
  const identity = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  for (let i = 0; i < n; i++) {
    const p: Vec3 = [positions[3 * i], positions[3 * i + 1], positions[3 * i + 2]];
    let rotation = identity;
    if (up || octUp) {
      const u: Vec3 = up ? [up[3 * i], up[3 * i + 1], up[3 * i + 2]] : octDecode(octUp![2 * i], octUp![2 * i + 1]);
      const r: Vec3 = right ? [right[3 * i], right[3 * i + 1], right[3 * i + 2]] : octDecode(octRight![2 * i], octRight![2 * i + 1]);
      rotation = [...r, ...u, ...normalize(cross(r, u))];
    } else if (enu) {
      rotation = enuRotation([p[0] + rtc[0], p[1] + rtc[1], p[2] + rtc[2]]);
    }
    const m = roundTrip(rotation);
    let s: Vec3 = [1, 1, 1];
    if (scales && Number.isFinite(scales[i])) s = [scales[i], scales[i], scales[i]];
    if (nonUniform) s = [s[0] * nonUniform[3 * i], s[1] * nonUniform[3 * i + 1], s[2] * nonUniform[3 * i + 2]];
    const out = matrices.subarray(16 * i, 16 * i + 16);
    for (let c = 0; c < 3; c++) for (let r = 0; r < 3; r++) out[4 * c + r] = m[3 * c + r] * s[c];
    out[12] = p[0] + rtc[0];
    out[13] = p[1] + rtc[1];
    out[14] = p[2] + rtc[2];
    out[15] = 1;
    batchIds[i] = ids ? ids[i] : i;
  }
  return { matrices, batchIds };
}

const empty = (): Model => ({ primitives: [], materials: [], images: [] });

function content(kind: TileContent["kind"], model: Model, rest: Partial<TileContent> = {}): TileContent {
  return { kind, model, rtc: null, batchLength: 0, batchTable: null, batchBinary: new Uint8Array(0), instances: null, parts: [], ...rest };
}

/** A b3dm's tables and its glb, or null when `bytes` is not a b3dm. */
export function splitB3dm(bytes: Uint8Array): { rtc: TileContent["rtc"]; batchLength: number; batchTable: Record<string, unknown> | null; batchBinary: Uint8Array; glb: Uint8Array } | null {
  if (bytes.length < 4 || viewOf(bytes).getUint32(0, true) !== B3DM) return null;
  const t = readTables(bytes, "b3dm", B3DM_HEADER_BYTES);
  const center = globalFloats(t.featureTable, t.featureBinary, "RTC_CENTER", 3);
  const rtc: TileContent["rtc"] = center ? [center[0], center[1], center[2]] : null;
  const batchLength = Number.isInteger(t.featureTable.BATCH_LENGTH) ? t.featureTable.BATCH_LENGTH : 0;
  return { rtc, batchLength, batchTable: t.batchTable, batchBinary: t.batchBinary, glb: t.body };
}

type Load = (uri: string) => Promise<Uint8Array>;

/** An i3dm's model, embedded or by URI (whose own URIs then resolve beside it), and its instances. */
async function readI3dm(bytes: Uint8Array, load: Load, meshopt?: MeshoptDecode, draco?: DracoDecode): Promise<TileContent> {
  const t = readTables(bytes, "i3dm", I3DM_HEADER_BYTES);
  const format = viewOf(bytes).getUint32(28, true);
  if (!t.body.length) throw new Error("the i3dm has no glTF");
  const instances = readInstances(t.featureTable, t.featureBinary);
  let model: Model;
  if (format === 1) {
    model = await readGltf(t.body, load, meshopt, draco);
  } else if (format === 0) {
    const uri = new TextDecoder().decode(t.body).replace(/[\s\0]+$/, "");
    const dir = uri.slice(0, uri.lastIndexOf("/") + 1);
    const beside = (u: string) => (/^[a-z][a-z0-9+.-]*:|^\//i.test(u) ? u : dir + u);
    model = await readGltf(await load(uri), (u) => load(beside(u)), meshopt, draco);
  } else {
    throw new Error("the i3dm's gltfFormat is neither 0 nor 1");
  }
  const batch = { batchLength: instances.batchIds.length, batchTable: t.batchTable, batchBinary: t.batchBinary };
  return content("i3dm", model, { ...batch, instances });
}

const GL_BYTE = 5121;
const GL_FLOAT = 5126;
const attribute = (data: Attribute["data"], size: number, type: number, normalized = false): Attribute => ({ data, size, type, normalized });

/** The Draco-compressed semantics of a pnts (3DTILES_draco_point_compression), decoded by unique id. */
function dracoPoints(ft: Json, bin: Uint8Array, bt: Json | null, draco?: DracoDecode): { feature: Map<string, Attribute>; batch: Map<string, Attribute> } | null {
  const ext = ft.extensions?.["3DTILES_draco_point_compression"];
  if (!ext) return null;
  const at = ext.byteOffset;
  const length = ext.byteLength;
  if (!Number.isInteger(at) || !Number.isInteger(length) || at < 0 || length < 0 || at + length > bin.length) throw new Error("the pnts' Draco data runs past the feature table");
  if (!draco) throw new Error("Draco compression is not available");
  const decoded = draco(bin.subarray(at, at + length));
  const pick = (properties: unknown) => {
    const out = new Map<string, Attribute>();
    if (!properties || typeof properties !== "object") return out;
    for (const [name, id] of Object.entries(properties)) {
      const a = decoded.attributes.get(Number(id));
      if (!a) throw new Error(`the pnts' Draco data has no attribute ${id}`);
      out.set(name, a);
    }
    return out;
  };
  return { feature: pick(ext.properties), batch: pick(bt?.extensions?.["3DTILES_draco_point_compression"]?.properties) };
}

/** A pnts as one POINTS primitive: positions (dequantized), colors, normals and batch ids per point. */
function readPnts(bytes: Uint8Array, draco?: DracoDecode): TileContent {
  const t = readTables(bytes, "pnts", PNTS_HEADER_BYTES);
  const ft = t.featureTable;
  const bin = t.featureBinary;
  const n = ft.POINTS_LENGTH;
  if (!Number.isInteger(n) || n < 0) throw new Error("the pnts has no POINTS_LENGTH");
  if (n > MAX_POINTS) throw new Error(`the pnts has more than ${MAX_POINTS} points`);
  const compressed = dracoPoints(ft, bin, t.batchTable, draco);
  const semantic = (name: string, type: string, size: number) => {
    const d = compressed?.feature.get(name);
    if (d) {
      if (d.data.length < n * size) throw new Error(`${name} has too few values`);
      return d.data;
    }
    return perInstance(ft, bin, name, type, size, n);
  };
  const rtc = globalFloats(ft, bin, "RTC_CENTER", 3) ?? [0, 0, 0];
  const attributes: Record<string, Attribute> = {};
  const position = semantic("POSITION", "FLOAT", 3);
  if (position) {
    attributes.POSITION = attribute(Float32Array.from(position.length > 3 * n ? Array.prototype.slice.call(position, 0, 3 * n) : position), 3, GL_FLOAT);
  } else {
    const quantized = semantic("POSITION_QUANTIZED", "UNSIGNED_SHORT", 3);
    if (!quantized) throw new Error("the pnts has neither POSITION nor POSITION_QUANTIZED");
    const offset = globalFloats(ft, bin, "QUANTIZED_VOLUME_OFFSET", 3);
    const scale = globalFloats(ft, bin, "QUANTIZED_VOLUME_SCALE", 3);
    if (!offset || !scale) throw new Error("POSITION_QUANTIZED needs QUANTIZED_VOLUME_OFFSET and QUANTIZED_VOLUME_SCALE");
    // The volume's offset goes with RTC_CENTER, in f64.
    attributes.POSITION = attribute(Float32Array.from({ length: 3 * n }, (_, i) => (quantized[i] / 65535) * scale[i % 3]), 3, GL_FLOAT);
    for (let k = 0; k < 3; k++) rtc[k] += offset[k];
  }
  const rgba = semantic("RGBA", "UNSIGNED_BYTE", 4);
  const rgb = rgba ? null : semantic("RGB", "UNSIGNED_BYTE", 3);
  const rgb565 = rgba || rgb ? null : semantic("RGB565", "UNSIGNED_SHORT", 1);
  if (rgba) attributes.COLOR_0 = attribute(Uint8Array.from(Array.prototype.slice.call(rgba, 0, 4 * n)), 4, GL_BYTE, true);
  else if (rgb) attributes.COLOR_0 = attribute(Uint8Array.from(Array.prototype.slice.call(rgb, 0, 3 * n)), 3, GL_BYTE, true);
  else if (rgb565) {
    const c = new Uint8Array(3 * n);
    for (let i = 0; i < n; i++) {
      const v = rgb565[i];
      c.set([((v >> 11) & 31) * (255 / 31), ((v >> 5) & 63) * (255 / 63), (v & 31) * (255 / 31)].map(Math.round), 3 * i);
    }
    attributes.COLOR_0 = attribute(c, 3, GL_BYTE, true);
  }
  const normal = semantic("NORMAL", "FLOAT", 3);
  const oct = normal ? null : semantic("NORMAL_OCT16P", "UNSIGNED_BYTE", 2);
  if (normal) attributes.NORMAL = attribute(Float32Array.from(Array.prototype.slice.call(normal, 0, 3 * n)), 3, GL_FLOAT);
  else if (oct) attributes.NORMAL = attribute(Float32Array.from({ length: 3 * n }, (_, i) => octDecode(oct[2 * Math.floor(i / 3)], oct[2 * Math.floor(i / 3) + 1], 255)[i % 3]), 3, GL_FLOAT);
  const ids = semantic("BATCH_ID", "UNSIGNED_SHORT", 1);
  const batchTable = t.batchTable;
  // Without BATCH_ID the batch table has a row per point.
  if (ids) attributes._BATCHID = attribute(Float32Array.from(Array.prototype.slice.call(ids, 0, n)), 1, GL_FLOAT);
  else if (batchTable) attributes._BATCHID = attribute(Float32Array.from({ length: n }, (_, i) => i), 1, GL_FLOAT);
  const batchLength = ids ? (Number.isInteger(ft.BATCH_LENGTH) ? ft.BATCH_LENGTH : 0) : batchTable ? n : 0;
  if (batchTable && compressed) {
    for (const [name, a] of compressed.batch) {
      const value = Array.from({ length: batchLength }, (_, i) => (a.size === 1 ? a.data[i] : Array.prototype.slice.call(a.data, i * a.size, (i + 1) * a.size)));
      Object.defineProperty(batchTable, name, { value, enumerable: true, writable: true, configurable: true });
    }
    delete batchTable.extensions;
  }
  const constant = globalFloats(ft, bin, "CONSTANT_RGBA", 4);
  const color: Material["color"] = constant ? [constant[0] / 255, constant[1] / 255, constant[2] / 255, constant[3] / 255] : [1, 1, 1, 1];
  const material: Material = { color, alphaMode: rgba || color[3] < 1 ? "BLEND" : "OPAQUE", alphaCutoff: 0.5, doubleSided: true, unlit: !attributes.NORMAL };
  const matrix = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  const model: Model = { primitives: [{ attributes, mode: 0, material: 0, matrix }], materials: [material], images: [] };
  return content("pnts", model, { rtc: [rtc[0], rtc[1], rtc[2]], batchLength, batchTable, batchBinary: t.batchBinary });
}

/** A cmpt's inner tiles, nested cmpts flattened into `parts`. */
async function readCmpt(bytes: Uint8Array, load: Load, depth: number, meshopt?: MeshoptDecode, draco?: DracoDecode): Promise<TileContent> {
  if (depth > MAX_COMPOSITE_DEPTH) throw new Error(`cmpt tiles nest deeper than ${MAX_COMPOSITE_DEPTH}`);
  const view = viewOf(bytes);
  if (bytes.length < CMPT_HEADER_BYTES) throw new Error("the cmpt header is cut short");
  if (view.getUint32(4, true) !== 1) throw new Error("only cmpt version 1 is read");
  const length = view.getUint32(8, true);
  if (length > bytes.length || length < CMPT_HEADER_BYTES) throw new Error("the cmpt is cut short");
  const count = view.getUint32(12, true);
  if (count > MAX_COMPOSITE_TILES) throw new Error(`the cmpt has more than ${MAX_COMPOSITE_TILES} tiles`);
  const out = content("cmpt", empty());
  let at = CMPT_HEADER_BYTES;
  for (let i = 0; i < count; i++) {
    if (at + INNER_HEADER_BYTES > length) throw new Error("the cmpt's tiles run past the file");
    const size = view.getUint32(at + 8, true);
    if (size < INNER_HEADER_BYTES || at + size > length) throw new Error("a cmpt tile runs past the file");
    const magic = view.getUint32(at, true);
    const inner = bytes.subarray(at, at + size);
    at += size;
    if (magic === CMPT) {
      const nested = await readCmpt(inner, load, depth + 1, meshopt, draco);
      out.parts.push(...nested.parts);
    } else if (magic === B3DM || magic === I3DM || magic === PNTS || magic === GLB) {
      out.parts.push(await readTileContent(inner, load, meshopt, draco));
    } else {
      throw new Error("a cmpt tile is neither b3dm, i3dm, cmpt, pnts nor glTF");
    }
    if (out.parts.length > MAX_COMPOSITE_TILES) throw new Error(`the cmpt has more than ${MAX_COMPOSITE_TILES} tiles`);
  }
  return out;
}

/** Reads the b3dm, i3dm, pnts, cmpt, glb or glTF in `bytes`; `load` fetches URIs relative to the tile. */
export async function readTileContent(bytes: Uint8Array, load: Load, meshopt?: MeshoptDecode, draco?: DracoDecode): Promise<TileContent> {
  const magic = bytes.length >= 4 ? viewOf(bytes).getUint32(0, true) : 0;
  if (magic === I3DM) return readI3dm(bytes, load, meshopt, draco);
  if (magic === CMPT) return readCmpt(bytes, load, 0, meshopt, draco);
  if (magic === PNTS) return readPnts(bytes, draco);
  const b3dm = splitB3dm(bytes);
  const model = await readGltf(b3dm ? b3dm.glb : bytes, load, meshopt, draco);
  if (!b3dm) return content("glTF", model, { rtc: model.rtc ?? null });
  return content("b3dm", model, { rtc: b3dm.rtc ?? model.rtc ?? null, batchLength: b3dm.batchLength, batchTable: b3dm.batchTable, batchBinary: b3dm.batchBinary });
}
