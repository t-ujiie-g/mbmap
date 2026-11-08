// glTF 2.0 for mbmap/3d: a .glb or .gltf read into flat primitives (each attribute as its own compact
// typed array, sparse accessors applied, the node's world matrix), materials and image bytes. Buffer
// views compressed with EXT_meshopt_compression or KHR_meshopt_compression go through `meshopt`;
// quantized attributes (KHR_mesh_quantization) stay quantized for the GPU. Import-free.

/** Components per element of an accessor type. */
const COMPONENTS: Record<string, number> = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };

/** Bytes per component of each glTF component type (WebGL's enums). */
const COMPONENT_BYTES: Record<number, number> = { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 };

/** Caps on what a model may hold: its JSON, output bytes, elements and node depth. */
export const MAX_GLTF_JSON_BYTES = 64 << 20;
export const MAX_MODEL_BYTES = 512 << 20;
export const MAX_NODE_DEPTH = 64;

const GLB_MAGIC = 0x46546c67;
const CHUNK_JSON = 0x4e4f534a;
const CHUNK_BIN = 0x004e4942;

export type Typed = Int8Array | Uint8Array | Int16Array | Uint16Array | Uint32Array | Float32Array;

/** An attribute's values: `size` components of `type` (a WebGL enum) per vertex, `normalized` as glTF says. */
export interface Attribute {
  data: Typed;
  size: number;
  type: number;
  normalized: boolean;
}

/** A material's base color texture: `image` index, its sampler, `texCoord` set and KHR_texture_transform `matrix` (column-major 3x3). */
export interface TextureRef {
  image: number;
  wrapS: number;
  wrapT: number;
  minFilter: number;
  magFilter: number;
  texCoord: number;
  matrix?: Float64Array;
}

/** What mbmap draws of a material: base color factor and texture, alpha mode and cutoff, `unlit` (KHR_materials_unlit). */
export interface Material {
  color: [number, number, number, number];
  texture?: TextureRef;
  alphaMode: "OPAQUE" | "MASK" | "BLEND";
  alphaCutoff: number;
  doubleSided: boolean;
  unlit: boolean;
}

/**
 * One set of a primitive's feature IDs: per vertex from `attribute` (`_BATCHID`, or EXT_mesh_features'
 * `_FEATURE_ID_n`), else `implicit`, `offset + floor(vertex / repeat)` (1 and 0 unless a draft's fields say).
 * `nullFeatureId` marks vertices of no feature; `featureCount` is unknown for `_BATCHID` (the b3dm's BATCH_LENGTH).
 */
export interface FeatureIds {
  attribute?: Attribute;
  implicit?: { offset: number; repeat: number };
  nullFeatureId?: number;
  featureCount?: number;
  propertyTable?: number;
  label?: string;
}

/** One primitive of a mesh in the scene: `mode` a WebGL draw mode, `material` an index or -1, `matrix` its node's world matrix (column-major), `featureIds` when it has any. */
export interface Primitive {
  attributes: Record<string, Attribute>;
  indices?: Uint8Array | Uint16Array | Uint32Array;
  mode: number;
  material: number;
  matrix: Float64Array;
  featureIds?: FeatureIds[];
}

/** EXT_structural_metadata: `schema` and `propertyTables` as the JSON has them, and copies of the buffer views the tables reference. */
export interface StructuralMetadata {
  schema: Record<string, any>;
  propertyTables: Record<string, any>[];
  bufferViews: Record<number, Uint8Array>;
}

/** An image's encoded bytes and media type. */
export interface ImageData {
  bytes: Uint8Array;
  mimeType: string;
}

/** `rtc` is the CESIUM_RTC extension's center, which 3D Tiles 1.0 contents may use. */
export interface Model {
  primitives: Primitive[];
  materials: Material[];
  images: ImageData[];
  rtc?: [number, number, number];
  metadata?: StructuralMetadata;
}

/** A Draco mesh decoded: its corner indices and its attributes by Draco unique id. */
export interface DracoMesh {
  indices: Uint32Array;
  attributes: Map<number, Attribute>;
}

/** Decodes a KHR_draco_mesh_compression buffer view (throws on malformed data). */
export type DracoDecode = (bytes: Uint8Array) => DracoMesh;

/** MeshoptDecoder.decodeGltfBuffer's arguments: writes `count` elements of `size` bytes into `target`. */
export type MeshoptDecode = (target: Uint8Array, count: number, size: number, source: Uint8Array, mode: string, filter: string) => void;

/** The extensions read; a model requiring another is refused. */
export const EXTENSIONS = new Set([
  "KHR_mesh_quantization",
  "KHR_texture_transform",
  "KHR_materials_unlit",
  "EXT_meshopt_compression",
  "KHR_meshopt_compression",
  "EXT_texture_webp",
  "CESIUM_RTC",
  "KHR_draco_mesh_compression",
  "EXT_mesh_features",
  "EXT_structural_metadata",
]);

/** Splits a .glb into its JSON and binary chunk; a .gltf (JSON text) has no binary chunk. */
export function splitGlb(bytes: Uint8Array): { json: unknown; bin?: Uint8Array } {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 12 || view.getUint32(0, true) !== GLB_MAGIC) {
    if (bytes.length > MAX_GLTF_JSON_BYTES) throw new Error("the glTF JSON is too large");
    return { json: JSON.parse(new TextDecoder().decode(bytes)) };
  }
  if (view.getUint32(4, true) !== 2) throw new Error("only glTF 2.0 is read");
  const length = Math.min(view.getUint32(8, true), bytes.length);
  let json: unknown;
  let bin: Uint8Array | undefined;
  for (let at = 12; at + 8 <= length; ) {
    const size = view.getUint32(at, true);
    const type = view.getUint32(at + 4, true);
    const start = at + 8;
    if (start + size > length) throw new Error("a GLB chunk runs past the file");
    if (type === CHUNK_JSON && json === undefined) {
      if (size > MAX_GLTF_JSON_BYTES) throw new Error("the glTF JSON is too large");
      json = JSON.parse(new TextDecoder().decode(bytes.subarray(start, start + size)));
    } else if (type === CHUNK_BIN && bin === undefined) {
      bin = bytes.subarray(start, start + size);
    }
    at = start + ((size + 3) & ~3);
  }
  if (json === undefined) throw new Error("the GLB has no JSON chunk");
  return { json, bin };
}

/** The bytes of a `data:` URI, or undefined for another URI. */
function dataUri(uri: string): Uint8Array | undefined {
  const m = /^data:[^,]*?(;base64)?,/.exec(uri);
  if (!m) return undefined;
  const body = uri.slice(m[0].length);
  if (!m[1]) return new TextEncoder().encode(decodeURIComponent(body));
  const text = atob(body);
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i);
  return out;
}

const obj = (v: unknown): Record<string, any> => (v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, any>) : {});
const list = (v: unknown): any[] => (Array.isArray(v) ? v : []);
const int = (v: unknown, fallback = 0): number => (Number.isInteger(v) && (v as number) >= 0 ? (v as number) : fallback);
const num = (v: unknown, fallback: number): number => (typeof v === "number" && Number.isFinite(v) ? v : fallback);

/** Column-major `a` times `b` (4x4). */
export function multiply(a: ArrayLike<number>, b: ArrayLike<number>): Float64Array {
  const out = new Float64Array(16);
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) {
      out[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3];
    }
  }
  return out;
}

/** A node's local matrix: its `matrix`, else translation, rotation (a quaternion) and scale. */
function localMatrix(node: Record<string, any>): Float64Array {
  const m = list(node.matrix);
  if (m.length === 16 && m.every((v) => typeof v === "number")) return Float64Array.from(m);
  const t = list(node.translation);
  const r = list(node.rotation);
  const s = list(node.scale);
  const [tx, ty, tz] = [num(t[0], 0), num(t[1], 0), num(t[2], 0)];
  const [x, y, z, w] = [num(r[0], 0), num(r[1], 0), num(r[2], 0), num(r[3], 1)];
  const [sx, sy, sz] = [num(s[0], 1), num(s[1], 1), num(s[2], 1)];
  return new Float64Array([
    (1 - 2 * (y * y + z * z)) * sx, 2 * (x * y + z * w) * sx, 2 * (x * z - y * w) * sx, 0,
    2 * (x * y - z * w) * sy, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z + x * w) * sy, 0,
    2 * (x * z + y * w) * sz, 2 * (y * z - x * w) * sz, (1 - 2 * (x * x + y * y)) * sz, 0,
    tx, ty, tz, 1,
  ]);
}

/** KHR_texture_transform's matrix: translation times rotation times scale, column-major. */
export function textureTransform(t: Record<string, any>): Float64Array {
  const offset = list(t.offset);
  const scale = list(t.scale);
  const r = num(t.rotation, 0);
  const [ox, oy, sx, sy] = [num(offset[0], 0), num(offset[1], 0), num(scale[0], 1), num(scale[1], 1)];
  const c = Math.cos(r);
  const s = Math.sin(r);
  return new Float64Array([c * sx, s * sx, 0, -s * sy, c * sy, 0, ox, oy, 1]);
}

/**
 * Reads a glTF from `bytes` (.glb or .gltf JSON): `load` fetches the URIs of its other buffers and
 * images (relative to the model), `meshopt` and `draco` decode compressed buffer views and primitives.
 */
export async function readGltf(bytes: Uint8Array, load: (uri: string) => Promise<Uint8Array>, meshopt?: MeshoptDecode, draco?: DracoDecode): Promise<Model> {
  const { json, bin } = splitGlb(bytes);
  const gltf = obj(json);
  if (!/^2\./.test(String(obj(gltf.asset).version))) throw new Error("only glTF 2.0 is read");
  const required = list(gltf.extensionsRequired).filter((e) => !EXTENSIONS.has(e));
  if (required.length) throw new Error(`unsupported glTF extensions: ${required.join(", ")}`);
  let budget = MAX_MODEL_BYTES;
  const spend = (n: number) => {
    budget -= n;
    if (budget < 0) throw new Error("the model is too large");
  };

  const buffers = await Promise.all(
    list(gltf.buffers).map(async (b, i) => {
      const buffer = obj(b);
      if (typeof buffer.uri === "string") return dataUri(buffer.uri) ?? (await load(buffer.uri));
      if (i === 0 && bin) return bin;
      // A meshopt fallback buffer may hold no data.
      return new Uint8Array(0);
    }),
  );

  const views = list(gltf.bufferViews).map(obj);
  const viewData: (Uint8Array | undefined)[] = [];
  const viewBytes = (index: number): Uint8Array => {
    const cached = viewData[index];
    if (cached) return cached;
    const view = views[index];
    if (!view) throw new Error(`no buffer view ${index}`);
    const ext = obj(view.extensions);
    const packed = obj(ext.KHR_meshopt_compression ?? ext.EXT_meshopt_compression);
    let data: Uint8Array;
    if (Object.keys(packed).length) {
      if (!meshopt) throw new Error("meshopt compression is not available");
      const source = slice(buffers[int(packed.buffer, -1)], int(packed.byteOffset), int(packed.byteLength, -1));
      const count = int(packed.count, -1);
      const stride = int(packed.byteStride, -1);
      if (count < 0 || stride <= 0 || count * stride > MAX_MODEL_BYTES) throw new Error("bad meshopt buffer view");
      spend(count * stride);
      data = new Uint8Array(count * stride);
      meshopt(data, count, stride, source, String(packed.mode), String(packed.filter ?? "NONE"));
    } else {
      data = slice(buffers[int(view.buffer, -1)], int(view.byteOffset), int(view.byteLength, -1));
    }
    viewData[index] = data;
    return data;
  };

  const accessors = list(gltf.accessors).map(obj);
  const readCache = new Map<number, Attribute>();
  const readAccessor = (index: number): Attribute => {
    const cached = readCache.get(index);
    if (cached) return cached;
    const a = accessors[index];
    if (!a) throw new Error(`no accessor ${index}`);
    const type = a.componentType;
    const bytesPer = COMPONENT_BYTES[type];
    const size = COMPONENTS[a.type];
    const count = int(a.count, -1);
    if (!bytesPer || !size || count < 0) throw new Error(`accessor ${index} is not an attribute`);
    const length = count * size;
    spend(length * bytesPer);
    const data = typed(type, length);
    if (a.bufferView !== undefined) {
      const viewIndex = int(a.bufferView, -1);
      const view = viewBytes(viewIndex);
      const element = size * bytesPer;
      const stride = int(views[viewIndex].byteStride, 0) || element;
      const offset = int(a.byteOffset);
      if (count > 0 && offset + stride * (count - 1) + element > view.length) throw new Error(`accessor ${index} runs past its buffer view`);
      const out = new Uint8Array(data.buffer);
      for (let i = 0; i < count; i++) out.set(view.subarray(offset + i * stride, offset + i * stride + element), i * element);
    }
    const sparse = obj(a.sparse);
    if (int(sparse.count) > 0) applySparse(data, size, count, sparse, viewBytes);
    const attribute: Attribute = { data, size, type, normalized: a.normalized === true };
    readCache.set(index, attribute);
    return attribute;
  };

  const materials: Material[] = list(gltf.materials).map((m) => readMaterial(obj(m), list(gltf.textures).map(obj), list(gltf.samplers).map(obj)));
  const images: ImageData[] = await Promise.all(
    list(gltf.images).map(async (im) => {
      const image = obj(im);
      if (typeof image.uri === "string") {
        const bytes = dataUri(image.uri) ?? (await load(image.uri));
        const mime = /^data:([^;,]*)/.exec(image.uri)?.[1] || (typeof image.mimeType === "string" ? image.mimeType : guessMime(image.uri));
        return { bytes, mimeType: mime };
      }
      const bytes = viewBytes(int(image.bufferView, -1));
      return { bytes, mimeType: typeof image.mimeType === "string" ? image.mimeType : "image/png" };
    }),
  );

  const nodes = list(gltf.nodes).map(obj);
  const meshes = list(gltf.meshes).map(obj);
  const primitives: Primitive[] = [];
  const scenes = list(gltf.scenes).map(obj);
  let roots: number[];
  if (scenes.length) roots = list(scenes[int(gltf.scene, 0)]?.nodes).map((n) => int(n, -1));
  else {
    const children = new Set(nodes.flatMap((n) => list(n.children)));
    roots = nodes.map((_, i) => i).filter((i) => !children.has(i));
  }
  const visit = (index: number, parent: Float64Array, depth: number, seen: Set<number>) => {
    const node = nodes[index];
    if (!node || seen.has(index) || depth > MAX_NODE_DEPTH) throw new Error("the node tree is malformed");
    seen.add(index);
    const matrix = multiply(parent, localMatrix(node));
    if (node.mesh !== undefined) {
      const mesh = meshes[int(node.mesh, -1)];
      if (!mesh) throw new Error(`no mesh ${node.mesh}`);
      for (const p of list(mesh.primitives).map(obj)) {
        const attributes: Record<string, Attribute> = {};
        const compressed = obj(obj(p.extensions).KHR_draco_mesh_compression);
        const ids = obj(compressed.attributes);
        let decoded: DracoMesh | undefined;
        if (Object.keys(compressed).length) {
          if (!draco) throw new Error("Draco compression is not available");
          decoded = draco(viewBytes(int(compressed.bufferView, -1)));
          spend(decoded.indices.byteLength);
        }
        for (const [name, accessor] of Object.entries(obj(p.attributes))) {
          const id = ids[name];
          if (decoded && id !== undefined) {
            const a = decoded.attributes.get(int(id, -1));
            if (!a) throw new Error(`the Draco mesh has no attribute ${id}`);
            spend(a.data.byteLength);
            attributes[name] = { ...a, normalized: accessors[int(accessor, -1)]?.normalized === true };
          } else {
            attributes[name] = readAccessor(int(accessor, -1));
          }
        }
        if (!attributes.POSITION) continue;
        let indices: Primitive["indices"];
        if (decoded) {
          indices = decoded.indices;
        } else if (p.indices !== undefined) {
          const a = readAccessor(int(p.indices, -1));
          if (!(a.data instanceof Uint8Array || a.data instanceof Uint16Array || a.data instanceof Uint32Array) || a.size !== 1) throw new Error("indices must be unsigned scalars");
          indices = a.data;
        }
        const primitive: Primitive = { attributes, indices, mode: int(p.mode, 4), material: p.material === undefined ? -1 : int(p.material, -1), matrix };
        const featureIds = readFeatureIds(p, attributes);
        if (featureIds.length) primitive.featureIds = featureIds;
        primitives.push(primitive);
      }
    }
    for (const child of list(node.children)) visit(int(child, -1), matrix, depth + 1, seen);
    seen.delete(index);
  };
  const identity = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  for (const root of roots) visit(root, identity, 0, new Set());
  const center = list(obj(obj(gltf.extensions).CESIUM_RTC).center);
  const rtc = center.length === 3 && center.every((v) => typeof v === "number" && Number.isFinite(v)) ? (center as [number, number, number]) : undefined;
  const model: Model = { primitives, materials, images, rtc };
  const metadata = obj(obj(gltf.extensions).EXT_structural_metadata);
  if (Object.keys(metadata).length) model.metadata = readMetadata(metadata, viewBytes, spend);
  return model;
}

/** A primitive's EXT_mesh_features feature IDs (feature ID textures left out), else its `_BATCHID`. */
function readFeatureIds(p: Record<string, any>, attributes: Record<string, Attribute>): FeatureIds[] {
  const out: FeatureIds[] = [];
  for (const f of list(obj(obj(p.extensions).EXT_mesh_features).featureIds).map(obj)) {
    if (f.attribute === undefined && f.texture !== undefined) continue;
    const ids: FeatureIds = { featureCount: int(f.featureCount) };
    if (f.attribute !== undefined) {
      const attribute = attributes[`_FEATURE_ID_${int(f.attribute, -1)}`];
      if (!attribute || attribute.size !== 1) throw new Error(`no feature ID attribute ${f.attribute}`);
      ids.attribute = attribute;
    } else {
      ids.implicit = { offset: int(f.offset), repeat: Math.max(1, int(f.repeat, 1)) };
    }
    if (Number.isInteger(f.nullFeatureId) && f.nullFeatureId >= 0) ids.nullFeatureId = f.nullFeatureId;
    if (Number.isInteger(f.propertyTable) && f.propertyTable >= 0) ids.propertyTable = f.propertyTable;
    if (typeof f.label === "string") ids.label = f.label;
    out.push(ids);
  }
  if (!out.length && attributes._BATCHID?.size === 1) out.push({ attribute: attributes._BATCHID });
  return out;
}

/** The property tables of EXT_structural_metadata with their buffer views; an external schema (`schemaUri`) is not fetched. */
function readMetadata(ext: Record<string, any>, viewBytes: (i: number) => Uint8Array, spend: (n: number) => void): StructuralMetadata {
  const propertyTables = list(ext.propertyTables).map(obj);
  const bufferViews: Record<number, Uint8Array> = Object.create(null);
  for (const table of propertyTables) {
    for (const property of Object.values(obj(table.properties)).map(obj)) {
      for (const key of ["values", "arrayOffsets", "stringOffsets"]) {
        if (property[key] === undefined) continue;
        const index = int(property[key], -1);
        if (bufferViews[index]) continue;
        const bytes = viewBytes(index);
        spend(bytes.length);
        bufferViews[index] = bytes.slice();
      }
    }
  }
  return { schema: obj(ext.schema), propertyTables, bufferViews };
}

function slice(buffer: Uint8Array | undefined, offset: number, length: number): Uint8Array {
  if (!buffer || length < 0 || offset + length > buffer.length) throw new Error("a buffer view runs past its buffer");
  return buffer.subarray(offset, offset + length);
}

function typed(type: number, length: number): Typed {
  switch (type) {
    case 5120: return new Int8Array(length);
    case 5121: return new Uint8Array(length);
    case 5122: return new Int16Array(length);
    case 5123: return new Uint16Array(length);
    case 5125: return new Uint32Array(length);
    default: return new Float32Array(length);
  }
}

/** Writes a sparse accessor's values over `data` at its indices. */
function applySparse(data: Typed, size: number, count: number, sparse: Record<string, any>, viewBytes: (i: number) => Uint8Array): void {
  const n = int(sparse.count);
  const ix = obj(sparse.indices);
  const vs = obj(sparse.values);
  const indexType = ix.componentType;
  const indexBytes = COMPONENT_BYTES[indexType];
  if (indexType !== 5121 && indexType !== 5123 && indexType !== 5125) throw new Error("bad sparse indices");
  const indexView = viewBytes(int(ix.bufferView, -1));
  const valueView = viewBytes(int(vs.bufferView, -1));
  const io = int(ix.byteOffset);
  const vo = int(vs.byteOffset);
  const element = size * data.BYTES_PER_ELEMENT;
  if (io + n * indexBytes > indexView.length || vo + n * element > valueView.length) throw new Error("a sparse accessor runs past its buffer view");
  const indices = new DataView(indexView.buffer, indexView.byteOffset + io, n * indexBytes);
  const out = new Uint8Array(data.buffer);
  for (let i = 0; i < n; i++) {
    const at = indexBytes === 1 ? indices.getUint8(i) : indexBytes === 2 ? indices.getUint16(i * 2, true) : indices.getUint32(i * 4, true);
    if (at >= count) throw new Error("a sparse index is out of range");
    out.set(valueView.subarray(vo + i * element, vo + (i + 1) * element), at * element);
  }
}

function readMaterial(m: Record<string, any>, textures: Record<string, any>[], samplers: Record<string, any>[]): Material {
  const pbr = obj(m.pbrMetallicRoughness);
  const c = list(pbr.baseColorFactor);
  const color: Material["color"] = [num(c[0], 1), num(c[1], 1), num(c[2], 1), num(c[3], 1)];
  const mode = m.alphaMode === "MASK" || m.alphaMode === "BLEND" ? m.alphaMode : "OPAQUE";
  const material: Material = {
    color,
    alphaMode: mode,
    alphaCutoff: num(m.alphaCutoff, 0.5),
    doubleSided: m.doubleSided === true,
    unlit: "KHR_materials_unlit" in obj(m.extensions),
  };
  const info = obj(pbr.baseColorTexture);
  const texture = textures[int(info.index, -1)];
  if (texture) {
    const webp = obj(obj(texture.extensions).EXT_texture_webp);
    const image = webp.source !== undefined ? int(webp.source, -1) : int(texture.source, -1);
    const sampler = samplers[int(texture.sampler, -1)] ?? {};
    const transform = obj(obj(info.extensions).KHR_texture_transform);
    const hasTransform = Object.keys(transform).length > 0;
    if (image >= 0) {
      material.texture = {
        image,
        wrapS: int(sampler.wrapS, 10497),
        wrapT: int(sampler.wrapT, 10497),
        minFilter: int(sampler.minFilter, 9987),
        magFilter: int(sampler.magFilter, 9729),
        texCoord: hasTransform && transform.texCoord !== undefined ? int(transform.texCoord) : int(info.texCoord),
        matrix: hasTransform ? textureTransform(transform) : undefined,
      };
    }
  }
  return material;
}

function guessMime(uri: string): string {
  if (/\.webp$/i.test(uri)) return "image/webp";
  if (/\.jpe?g$/i.test(uri)) return "image/jpeg";
  return "image/png";
}
