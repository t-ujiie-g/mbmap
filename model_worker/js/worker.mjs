// Glue around the wasm-gc build of `model_worker` (meshopt, Draco): glTF models and their images, 3D tiles,
// I3S nodes, and LAS point clouds taken to WGS 84 through proj.wasm, for mbmap/3d (`npm/src/model`,
// `tiles`, `i3s`); messages are in docs/FORMATS.md ("Model worker messages").

import { transformPairs } from "../../data_worker/js/crs.mjs";
import { draco, lepcc, meshopt } from "./decode.mjs";
import { readCapped } from "../../worker/js/body.mjs";
import { MAX_MODEL_BYTES, readGltf } from "../../npm/src/model/gltf.ts";
import { horizontalWkt, MAX_LAS_BYTES, MAX_LAS_POINTS, readLas } from "../../npm/src/model/las.ts";
import { cartesian, MAX_I3S_BYTES, MAX_I3S_TEXTURE_BYTES, materialOf, readI3sGeometry } from "../../npm/src/i3s/content.ts";
import { readTileContent } from "../../npm/src/tiles/content.ts";
import { eastNorthUp, toCartesian } from "../../npm/src/tiles/geo.ts";

let wasmUrl = null;
let wasm = null;
// proj.wasm (with the host's Math, as proj4js computes) and the .prj WKT parser (prjwkt.js), each on first use.
const urls = {};
const loaded = {};
function lazy(name, start) {
  if (typeof urls[name] !== "string") return Promise.reject(new Error(`no URL for the ${name} module`));
  return (loaded[name] ??= start(urls[name]));
}
const proj = () => lazy("proj", (url) => WebAssembly.instantiateStreaming(fetch(url), { Math }).then(({ instance }) => instance.exports));
const prj = () => lazy("prj", (url) => import(url));

async function instance() {
  if (!wasm) {
    const { instance } = await WebAssembly.instantiateStreaming(fetch(wasmUrl), {});
    wasm = instance.exports;
  }
  return wasm;
}

const isHttp = (url) => url.protocol === "http:" || url.protocol === "https:" || url.protocol === "blob:" || url.protocol === "data:";

async function fetchBytes(url, max = MAX_MODEL_BYTES) {
  if (!isHttp(url)) throw new Error(`cannot load ${url.protocol} URLs`);
  const res = await fetch(url, { credentials: "omit" });
  if (!res.ok) throw new Error(`${url.href}: HTTP ${res.status}`);
  return readCapped(res, max);
}

/** Decodes an image's bytes into an ImageBitmap as uploaded (no premultiplying or color conversion). */
const bitmap = (image) =>
  createImageBitmap(new Blob([image.bytes], { type: image.mimeType }), { premultiplyAlpha: "none", colorSpaceConversion: "none" });

async function load({ url }) {
  const base = new URL(url);
  const bytes = await fetchBytes(base);
  const exports = await instance();
  const model = await readGltf(bytes, (uri) => fetchBytes(new URL(uri, base)), meshopt(exports), draco(exports));
  const images = await Promise.all(model.images.map(bitmap));
  return { primitives: model.primitives, materials: model.materials, images };
}

/** `bytes`, gunzipped (capped at `max`) when they are gzip data, as I3S resources stored raw may be. */
async function gunzip(bytes, max) {
  if (bytes[0] !== 0x1f || bytes[1] !== 0x8b) return bytes;
  return readCapped(new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"))), max);
}

/** The media type of JPEG or PNG bytes, else undefined (DDS and KTX2 textures are not drawn). */
const imageType = (b) => (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff ? "image/jpeg" : b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 ? "image/png" : undefined);

/** `bytes` given (an SLPK's entry, gunzipped by the caller), else those at `url`, capped at `max`. */
const resource = (bytes, url, max) => (bytes instanceof Uint8Array ? (bytes.length > max ? Promise.reject(new Error(`more than ${max} bytes`)) : Promise.resolve(bytes)) : fetchBytes(new URL(url), max));

/** An I3S node's geometry buffer (`buffer` of its definition) and JPEG or PNG texture, in east, north, up meters around its center. */
async function i3s({ url, geometry, buffer, texture, textureBytes, layer, node }) {
  const obj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
  const given = (bytes, at) => (bytes === undefined ? typeof at === "string" : bytes instanceof Uint8Array && at === undefined);
  const untextured = texture === undefined && textureBytes === undefined;
  if (!Number.isInteger(buffer) || buffer < 0 || !obj(layer) || !obj(node) || !given(geometry, url) || !(untextured || given(textureBytes, texture))) throw new Error("invalid arguments");
  const def = layer.geometryDefinitions?.[node.mesh?.geometry?.definition]?.geometryBuffers?.[buffer];
  const decoder = def?.compressedAttributes ? draco(await instance()) : undefined;
  const [bytes, image] = await Promise.all([
    resource(geometry, url, MAX_I3S_BYTES).then((b) => gunzip(b, MAX_I3S_BYTES)),
    untextured ? undefined : resource(textureBytes, texture, MAX_I3S_TEXTURE_BYTES).then((b) => gunzip(b, MAX_I3S_TEXTURE_BYTES)),
  ]);
  const { center, primitive, featureIds, count } = readI3sGeometry(bytes, layer, node, buffer, decoder);
  const mimeType = image && imageType(image);
  const images = mimeType ? [await bitmap({ bytes: image, mimeType })] : [];
  return { center, primitives: [primitive], materials: [materialOf(layer, node.mesh?.material?.definition, images.length > 0)], images, featureIds, count };
}

/** The typed array of each uncompressed PCSL attribute value type. */
const PCSL_TYPES = { UInt8: Uint8Array, UInt16: Uint16Array, UInt32: Uint32Array, Int8: Int8Array, Int16: Int16Array, Int32: Int32Array, Float32: Float32Array, Float64: Float64Array };

/**
 * An I3S point cloud node (each resource a URL or its bytes): its LEPCC xyz (longitude, latitude, height) in f32 east, north, up meters
 * around `center`, and the attributes asked for (`rgb` and `intensity` LEPCC-coded, `classification`
 * a plain array of `classType` values).
 */
async function pcsl({ url, center, rgb, intensity, classification, classType }) {
  const str = (v) => v === undefined || typeof v === "string" || v instanceof Uint8Array;
  if (!str(url) || url === undefined || !Array.isArray(center) || center.length !== 3 || !center.every(Number.isFinite) || ![rgb, intensity, classification].every(str)) throw new Error("invalid arguments");
  const codec = lepcc(await instance());
  // URLs, or the bytes an SLPK gave the main thread.
  const get = (u) => (u === undefined ? undefined : (u instanceof Uint8Array ? Promise.resolve(u) : fetchBytes(new URL(u), MAX_I3S_BYTES)).then((b) => gunzip(b, MAX_I3S_BYTES)));
  const [xyzBytes, rgbBytes, intensityBytes, classBytes] = await Promise.all([get(url), get(rgb), get(intensity), get(classification)]);
  const xyz = codec.xyz(xyzBytes);
  const count = xyz.length / 3;
  const origin = cartesian(center[0], center[1], center[2]);
  const m = eastNorthUp(origin);
  const positions = new Float32Array(3 * count);
  for (let i = 0; i < count; i++) {
    const p = cartesian(xyz[3 * i], xyz[3 * i + 1], xyz[3 * i + 2]);
    const d = [p[0] - origin[0], p[1] - origin[1], p[2] - origin[2]];
    for (let k = 0; k < 3; k++) positions[3 * i + k] = m[4 * k] * d[0] + m[4 * k + 1] * d[1] + m[4 * k + 2] * d[2];
  }
  const colors = rgbBytes ? codec.rgb(rgbBytes) : null;
  const intensities = intensityBytes ? codec.intensity(intensityBytes) : null;
  const Typed = Object.hasOwn(PCSL_TYPES, classType) ? PCSL_TYPES[classType] : Uint8Array;
  const classes = classBytes ? Uint8Array.from(new Typed(classBytes.buffer, classBytes.byteOffset, Math.floor(classBytes.byteLength / Typed.BYTES_PER_ELEMENT))) : null;
  for (const [name, a, size] of [["rgb", colors, 3], ["intensity", intensities, 1], ["classification", classes, 1]]) {
    if (a && a.length !== count * size) throw new Error(`I3S: the node's ${name} has ${a.length / size} values for ${count} points`);
  }
  return { center, positions, colors, intensity: intensities, classification: classes, count };
}

/** A tile's content as parts to draw: a cmpt's inner tiles, else the content itself. */
async function tile({ url }) {
  const base = new URL(url);
  const exports = await instance();
  const content = await readTileContent(await fetchBytes(base), (uri) => fetchBytes(new URL(uri, base)), meshopt(exports), draco(exports));
  const parts = content.kind === "cmpt" ? content.parts : [content];
  return {
    parts: await Promise.all(
      parts.map(async (c) => ({
        kind: c.kind,
        primitives: c.model.primitives,
        materials: c.model.materials,
        images: await Promise.all(c.model.images.map(bitmap)),
        rtc: c.rtc,
        batchLength: c.batchLength,
        batchTable: c.batchTable,
        batchBinary: c.batchBinary.slice(),
        instances: c.instances,
        metadata: c.model.metadata,
      })),
    ),
  };
}

// `@proj.DEFINITION_SLOTS` (proj/encoding.mbt), as data_worker/js/read.mjs's `isCrs`.
const DEFINITION_SLOTS = 34;
const isCrs = (c) => (Number.isInteger(c) && c > 0) || (c instanceof Float64Array && c.length === DEFINITION_SLOTS);
const isLonLat = (crs) => crs === 4326 || crs === 4979 || crs?.code === 4326 || crs?.code === 4979;
// Points per proj.wasm call: the pairs and the answer both sit in its memory.
const PAIRS_PER_CALL = 1 << 22;

/** The CRS of a LAS file's coordinates as proj.wasm takes them: `given`, else the file's EPSG code, else its WKT parsed. */
async function lasCrs(given, stated) {
  if (given !== undefined) return given;
  if (stated?.epsg !== undefined) return stated.epsg;
  if (stated?.wkt !== undefined) return (await prj()).parsePrj(horizontalWkt(stated.wkt));
  throw new Error("LAS: the file states no CRS; give crs");
}

/** Longitude, latitude and height per point of `positions` (x, y, z in `crs`), heights as they are. */
async function toLonLatHeight(positions, crs) {
  if (isLonLat(crs)) return positions;
  const exports = await proj();
  const n = positions.length / 3;
  const out = new Float64Array(positions.length);
  for (let start = 0; start < n; start += PAIRS_PER_CALL) {
    const m = Math.min(PAIRS_PER_CALL, n - start);
    const xy = new Float64Array(m * 2);
    for (let i = 0; i < m; i++) {
      xy[i * 2] = positions[(start + i) * 3];
      xy[i * 2 + 1] = positions[(start + i) * 3 + 1];
    }
    const lonLat = transformPairs(exports, crs, 4326, xy);
    for (let i = 0; i < m; i++) {
      const [lon, lat] = [lonLat[i * 2], lonLat[i * 2 + 1]];
      if (Number.isNaN(lon) || Number.isNaN(lat)) throw new Error("LAS: coordinates out of reach of the CRS");
      out.set([lon, lat, positions[(start + i) * 3 + 2]], (start + i) * 3);
    }
  }
  return out;
}

/**
 * A LAS point cloud at `url` (thinned to `maxPoints`) in east, north, up meters around the center of its
 * bounds, through the WGS 84 east-north-up frame there; `crs` (an EPSG code or a definition) overrides the file's.
 */
async function las({ url, maxPoints, crs }) {
  if (!(Number.isInteger(maxPoints) && maxPoints > 0 && maxPoints <= MAX_LAS_POINTS) || !(crs === undefined || isCrs(crs))) throw new Error("invalid arguments");
  const cloud = readLas(await fetchBytes(new URL(url), MAX_LAS_BYTES), maxPoints);
  const geo = await toLonLatHeight(cloud.positions, await lasCrs(crs, cloud.crs));
  const lo = [Infinity, Infinity, Infinity];
  const hi = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < geo.length; i++) {
    lo[i % 3] = Math.min(lo[i % 3], geo[i]);
    hi[i % 3] = Math.max(hi[i % 3], geo[i]);
  }
  const center = cloud.kept > 0 ? [0, 1, 2].map((k) => (lo[k] + hi[k]) / 2) : [0, 0, 0];
  const origin = toCartesian(center[0], center[1], center[2]);
  const m = eastNorthUp(origin);
  const positions = new Float32Array(geo.length);
  for (let i = 0; i < geo.length; i += 3) {
    const p = toCartesian(geo[i], geo[i + 1], geo[i + 2]);
    const [dx, dy, dz] = [p[0] - origin[0], p[1] - origin[1], p[2] - origin[2]];
    positions[i] = m[0] * dx + m[1] * dy + m[2] * dz;
    positions[i + 1] = m[4] * dx + m[5] * dy + m[6] * dz;
    positions[i + 2] = m[8] * dx + m[9] * dy + m[10] * dz;
  }
  const bounds = cloud.kept > 0 ? [lo[0], lo[1], lo[2], hi[0], hi[1], hi[2]] : [0, 0, 0, 0, 0, 0];
  const { colors, intensity, classification, count, kept } = cloud;
  return { center, positions, colors, intensity, classification, count, kept, bounds };
}

const OPS = { load, tile, las, i3s, pcsl };

/** Every ArrayBuffer and ImageBitmap of a model, a tile's parts, an I3S node or a point cloud, once each. */
function transferables(value) {
  if (value.positions) return [value.positions, value.colors, value.intensity, value.classification].filter(Boolean).map((a) => a.buffer);
  const out = new Set();
  for (const part of value.parts ?? [value]) {
    for (const image of part.images) out.add(image);
    for (const p of part.primitives) {
      for (const a of Object.values(p.attributes)) out.add(a.data.buffer);
      if (p.indices) out.add(p.indices.buffer);
    }
    if (part.instances) for (const a of [part.instances.matrices, part.instances.batchIds]) out.add(a.buffer);
    if (part.featureIds instanceof Float64Array) out.add(part.featureIds.buffer);
  }
  return [...out];
}

onmessage = async (e) => {
  const msg = e.data;
  if (msg?.type === "init" && wasmUrl === null && typeof msg.wasm === "string") {
    wasmUrl = msg.wasm;
    urls.proj = msg.proj;
    urls.prj = msg.prj;
  } else if (msg?.type === "call" && wasmUrl !== null && Number.isInteger(msg.id) && Object.hasOwn(OPS, msg.op) && (typeof msg.url === "string" || msg.op === "i3s" || msg.op === "pcsl")) {
    try {
      const value = await OPS[msg.op](msg);
      postMessage({ type: "result", id: msg.id, value }, transferables(value));
    } catch (err) {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    }
  }
};
