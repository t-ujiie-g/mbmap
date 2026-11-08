// draco (js build of bench/entry and the wasm-gc build of model_worker) vs draco3d 1.5.7's decoder:
// seeded grids, spheres, seamed meshes and triangle soups with position, normal, tex coord, color
// and generic attributes of every type, encoded by draco3d's encoder at every speed, both methods
// and many quantization settings; every Draco buffer of the PLATEAU fixture; and truncated or
// corrupted copies of them. Indices and attribute values must be bitwise identical, and the port
// must refuse exactly what draco3d refuses (or what passes its caps, counted apart).
// Usage: node draco/golden.mjs [--cases=N]; writes bench/results/draco-golden.json.
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { ENTRY_JS } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { writeInput } from "../../wasmio/js/host.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const require = createRequire(import.meta.url);
const draco3d = require("draco3d");

const CASES = Number(arg("cases", 60));
const MODEL_WASM = "_build/wasm-gc/release/build/model_worker/model_worker.wasm";
const PLATEAU = path.join(ROOT, "bench/fixtures/plateau-chiyoda/data");
const CAPS = { faces: 0x400000, points: 0x400000, attributes: 256, bytes: 0x10000000 };
const TYPE_LENGTH = [0, 1, 1, 2, 2, 4, 4, 8, 8, 4, 8, 1];

const mbt = await nodeImportJs(ENTRY_JS);
const { instance } = await WebAssembly.instantiate(await nodeFetchBytes(MODEL_WASM), {});
const gc = instance.exports;
let encoderModule = await draco3d.createEncoderModule({});
let dm = await draco3d.createDecoderModule({});
let restarts = 0;

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const random = rng(20261108);
const int = (n) => Math.floor(random() * n);
const pick = (a) => a[int(a.length)];

/** draco3d's decoding of `bytes` as the parsed "Draco output" fields, or null when it fails. */
async function reference(bytes) {
  let decoder, mesh;
  try {
    decoder = new dm.Decoder();
    mesh = new dm.Mesh();
    const status = decoder.DecodeArrayToMesh(new Int8Array(bytes.buffer, bytes.byteOffset, bytes.length), bytes.length, mesh);
    if (!status.ok()) return null;
    const numFaces = mesh.num_faces();
    const numPoints = mesh.num_points();
    if (numFaces > CAPS.faces || numPoints > CAPS.points || mesh.num_attributes() > CAPS.attributes) return "capped";
    const n = numFaces * 3;
    const ptr = dm._malloc(Math.max(4, n * 4));
    decoder.GetTrianglesUInt32Array(mesh, n * 4, ptr);
    const indices = new Uint32Array(dm.HEAPU8.buffer, ptr, n).slice();
    dm._free(ptr);
    const attributes = [];
    for (let i = 0; i < mesh.num_attributes(); i++) {
      const att = decoder.GetAttribute(mesh, i);
      const dataType = att.data_type();
      // The binding reads num_components as an int8, and GetAttributeDataArrayForAllPoints refuses
      // the attributes whose count is negative so; their values are not compared.
      const signedComponents = att.num_components();
      const numComponents = signedComponents & 0xff;
      const length = numPoints * numComponents * TYPE_LENGTH[dataType];
      if (length > CAPS.bytes) return "capped";
      let data = null;
      if ((dataType >= 1 && dataType <= 6 || dataType === 9) && signedComponents > 0) {
        const p = dm._malloc(Math.max(4, length));
        if (!decoder.GetAttributeDataArrayForAllPoints(mesh, att, dataType, length, p)) throw new Error("GetAttributeDataArrayForAllPoints failed");
        data = new Uint8Array(dm.HEAPU8.buffer, p, length).slice();
        dm._free(p);
      }
      attributes.push({ uniqueId: att.unique_id(), type: att.attribute_type(), dataType, numComponents, normalized: att.normalized(), length, data });
    }
    return { numFaces, numPoints, indices, attributes };
  } catch (e) {
    // An abort (out of memory) leaves the module unusable.
    restarts++;
    dm = await draco3d.createDecoderModule({});
    return "aborted";
  } finally {
    try {
      if (mesh) dm.destroy(mesh);
      if (decoder) dm.destroy(decoder);
    } catch {}
  }
}

/** docs/FORMATS.md "Draco output". */
function parse(out) {
  if (!out) return null;
  const view = new DataView(out.buffer, out.byteOffset, out.byteLength);
  const numFaces = view.getUint32(0, true), numPoints = view.getUint32(4, true), n = view.getUint32(8, true);
  const attributes = [];
  for (let i = 0; i < n; i++) {
    const at = 12 + 12 * i;
    attributes.push({
      uniqueId: view.getUint32(at, true),
      type: out[at + 4],
      dataType: out[at + 5],
      numComponents: out[at + 6],
      normalized: out[at + 7] === 1,
      length: view.getUint32(at + 8, true),
    });
  }
  let at = 12 + 12 * n;
  const indices = new Uint32Array(numFaces * 3);
  for (let i = 0; i < indices.length; i++, at += 4) indices[i] = view.getUint32(at, true);
  for (const a of attributes) {
    a.data = out.slice(at, at + a.length);
    at += Math.ceil(a.length / 4) * 4;
  }
  return { numFaces, numPoints, indices, attributes };
}

function oursJs(bytes) {
  const out = mbt.draco_decode(bytes);
  return out.length === 0 ? null : parse(out);
}

function oursGc(bytes) {
  writeInput(gc, [bytes], "draco data");
  const n = gc.draco_decode();
  if (n === -1) return null;
  if (n < 0) throw new Error(`draco_decode gave ${n}`);
  return parse(new Uint8Array(gc.memory.buffer, gc.output_addr(), n).slice());
}

function same(want, got) {
  if (want === null || got === null) return want === got;
  if (want.numFaces !== got.numFaces || want.numPoints !== got.numPoints) return false;
  if (!want.indices.every((v, i) => v === got.indices[i])) return false;
  if (want.attributes.length !== got.attributes.length) return false;
  return want.attributes.every((a, i) => {
    const b = got.attributes[i];
    if (a.uniqueId !== b.uniqueId || a.type !== b.type || a.dataType !== b.dataType || a.numComponents !== b.numComponents || a.normalized !== b.normalized || a.length !== b.length) return false;
    return a.data === null || a.data.every((v, k) => v === b.data[k]);
  });
}

const stats = {};
const failures = [];
async function compare(group, bytes) {
  const s = (stats[group] ??= { cases: 0, identical: 0, refused: 0, capped: 0, aborted: 0, differ: 0 });
  s.cases++;
  const want = await reference(bytes);
  const js = oursJs(bytes);
  const wasm = oursGc(bytes);
  if (want === "capped" || want === "aborted") {
    // draco3d decoded (or ran out of memory on) a mesh past the port's caps, which refuses it.
    if (js === null && wasm === null) {
      s[want]++;
      return null;
    }
  }
  if (same(want, js) && same(want, wasm)) {
    s.identical++;
    if (want === null) s.refused++;
  } else {
    s.differ++;
    if (failures.length < 12) {
      const show = (r) => (r === null ? "refused" : typeof r === "string" ? r : `${r.numFaces} faces ${r.numPoints} points`);
      failures.push({ group, bytes: bytes.length, want: show(want), js: show(js), wasm: show(wasm), hex: Buffer.from(bytes.subarray(0, 4096)).toString("hex") });
    }
  }
  return want;
}

// Meshes: positions, faces and attribute values of each kind.
function grid(w, h) {
  const pos = [], uv = [], faces = [];
  for (let y = 0; y <= h; y++) {
    for (let x = 0; x <= w; x++) {
      pos.push(x + (random() - 0.5) * 0.2, y + (random() - 0.5) * 0.2, Math.sin(x * 0.3) * Math.cos(y * 0.2) * 3);
      uv.push(x / w, y / h);
    }
  }
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * (w + 1) + x;
      faces.push(i, i + 1, i + w + 1, i + 1, i + w + 2, i + w + 1);
    }
  }
  return { pos, uv, faces };
}

function sphere(segments, rings, seam) {
  const pos = [], uv = [], faces = [];
  const cols = seam ? segments + 1 : segments;
  for (let r = 0; r <= rings; r++) {
    const phi = (r / rings) * Math.PI;
    for (let s = 0; s < cols; s++) {
      const th = (s / segments) * 2 * Math.PI;
      pos.push(Math.sin(phi) * Math.cos(th) * 10, Math.cos(phi) * 10, Math.sin(phi) * Math.sin(th) * 10);
      uv.push(s / segments, r / rings);
    }
  }
  for (let r = 0; r < rings; r++) {
    for (let s = 0; s < segments; s++) {
      const a = r * cols + s, b = r * cols + ((s + 1) % cols), c = a + cols, d = b + cols;
      if (r > 0) faces.push(a, b, c);
      if (r < rings - 1) faces.push(b, d, c);
    }
  }
  return { pos, uv, faces };
}

function soup(numTriangles, numPoints) {
  const pos = [], uv = [], faces = [];
  for (let i = 0; i < numPoints; i++) {
    pos.push((random() - 0.5) * 1000, (random() - 0.5) * 1000, (random() - 0.5) * 1000);
    uv.push(random(), random());
  }
  for (let i = 0; i < numTriangles; i++) {
    const a = int(numPoints);
    let b = int(numPoints), c = int(numPoints);
    if (b === a) b = (a + 1) % numPoints;
    if (c === a || c === b) c = (Math.max(a, b) + 1) % numPoints;
    faces.push(a, b, c);
  }
  return { pos, uv, faces };
}

/** A building-like box set as PLATEAU's LOD2 meshes are: flat faces with their own vertices. */
function boxes(count) {
  const pos = [], uv = [], faces = [];
  for (let k = 0; k < count; k++) {
    const x0 = random() * 500, y0 = random() * 500, w = 5 + random() * 30, d = 5 + random() * 30, h = 3 + random() * 80;
    const corners = [[x0, y0], [x0 + w, y0], [x0 + w, y0 + d], [x0, y0 + d]];
    for (let s = 0; s < 4; s++) {
      const [ax, ay] = corners[s], [bx, by] = corners[(s + 1) % 4];
      const base = pos.length / 3;
      pos.push(ax, ay, 0, bx, by, 0, bx, by, h, ax, ay, h);
      uv.push(0, 0, 1, 0, 1, 1, 0, 1);
      faces.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
    const base = pos.length / 3;
    for (const [cx, cy] of corners) pos.push(cx, cy, h), uv.push(random(), random());
    faces.push(base, base + 1, base + 2, base, base + 2, base + 3);
  }
  return { pos, uv, faces };
}

function normalsOf(pos, kind) {
  const n = new Float32Array(pos.length);
  for (let i = 0; i < pos.length; i += 3) {
    let x = pos[i], y = pos[i + 1], z = pos[i + 2];
    if (kind === "random") (x = random() - 0.5), (y = random() - 0.5), (z = random() - 0.5);
    if (kind === "axis") (x = pick([-1, 0, 1])), (y = pick([-1, 0, 1])), (z = x === 0 && y === 0 ? 1 : 0);
    const l = Math.hypot(x, y, z) || 1;
    n[i] = x / l, n[i + 1] = y / l, n[i + 2] = z / l;
  }
  return n;
}

const TYPED = { int8: Int8Array, uint8: Uint8Array, int16: Int16Array, uint16: Uint16Array, int32: Int32Array, uint32: Uint32Array };
const ADD = { int8: "AddInt8Attribute", uint8: "AddUInt8Attribute", int16: "AddInt16Attribute", uint16: "AddUInt16Attribute", int32: "AddInt32AttributeToMesh", uint32: "AddUInt32Attribute" };
const RANGE = { int8: [-128, 127], uint8: [0, 255], int16: [-32768, 32767], uint16: [0, 65535], int32: [-2147483648, 2147483647], uint32: [0, 4294967295] };

function integers(type, count, nc, smooth) {
  const out = new TYPED[type](count * nc);
  const [lo, hi] = RANGE[type];
  // The encoder's wrap transform refuses value ranges of 2^31 and more.
  const span = Math.min(hi - lo, smooth ? 50 : 2 ** 30);
  for (let i = 0; i < out.length; i++) out[i] = lo + Math.floor((smooth ? Math.sin(i * 0.01) * 0.5 + 0.5 : random()) * span);
  return out;
}

/** Encodes `geometry` with random attributes and settings; null when the encoder refuses it. */
function encode(geometry, settings) {
  const em = encoderModule;
  const builder = new em.MeshBuilder();
  const mesh = new em.Mesh();
  const encoder = new em.Encoder();
  const dracoArray = new em.DracoInt8Array();
  try {
    const numPoints = geometry.pos.length / 3;
    builder.AddFacesToMesh(mesh, geometry.faces.length / 3, new Uint32Array(geometry.faces));
    builder.AddFloatAttributeToMesh(mesh, em.POSITION, numPoints, 3, new Float32Array(geometry.pos));
    if (settings.normals) builder.AddFloatAttributeToMesh(mesh, em.NORMAL, numPoints, 3, normalsOf(geometry.pos, settings.normals));
    if (settings.uv) builder.AddFloatAttributeToMesh(mesh, em.TEX_COORD, numPoints, 2, new Float32Array(geometry.uv));
    if (settings.color === "uint8") {
      const id = builder.AddUInt8Attribute(mesh, em.COLOR, numPoints, 4, integers("uint8", numPoints, 4, false));
      builder.SetNormalizedFlagForAttribute(mesh, id, true);
    } else if (settings.color === "float") {
      builder.AddFloatAttributeToMesh(mesh, em.COLOR, numPoints, 3, new Float32Array(numPoints * 3).map(() => random()));
    }
    for (const g of settings.generic) {
      if (g.type === "float") builder.AddFloatAttributeToMesh(mesh, em.GENERIC, numPoints, g.nc, new Float32Array(numPoints * g.nc).map((_, i) => Math.sin(i) * 100));
      else builder[ADD[g.type]](mesh, em.GENERIC, numPoints, g.nc, integers(g.type, numPoints, g.nc, g.smooth));
    }
    if (settings.metadata) {
      const md = new em.Metadata();
      const mb = new em.MetadataBuilder();
      mb.AddStringEntry(md, "name", "mesh");
      mb.AddIntEntry(md, "id", 7);
      mb.AddDoubleEntry(md, "scale", 0.5);
      builder.AddMetadataToMesh(mesh, md);
      em.destroy(mb);
    }
    for (const [type, bits] of Object.entries(settings.bits)) if (bits > 0) encoder.SetAttributeQuantization(em[type], bits);
    if (settings.explicit) encoder.SetAttributeExplicitQuantization(em.POSITION, settings.explicit, 3, new Float32Array([-600, -600, -600]), 1200);
    encoder.SetSpeedOptions(settings.speed, settings.decodeSpeed);
    encoder.SetEncodingMethod(settings.sequential ? em.MESH_SEQUENTIAL_ENCODING : em.MESH_EDGEBREAKER_ENCODING);
    const n = encoder.EncodeMeshToDracoBuffer(mesh, dracoArray);
    if (n <= 0) return null;
    const out = new Uint8Array(n);
    for (let i = 0; i < n; i++) out[i] = dracoArray.GetValue(i);
    return out;
  } finally {
    em.destroy(dracoArray);
    em.destroy(encoder);
    em.destroy(mesh);
    em.destroy(builder);
  }
}

function randomSettings(c) {
  const bits = (lo, hi) => (random() < 0.15 ? 0 : lo + int(hi - lo + 1));
  const generic = [];
  for (let k = int(3); k > 0; k--) {
    generic.push({ type: pick(["float", "int8", "uint8", "int16", "uint16", "int32", "uint32"]), nc: 1 + int(4), smooth: random() < 0.5 });
  }
  return {
    normals: random() < 0.7 ? pick(["position", "random", "axis"]) : null,
    uv: random() < 0.7,
    color: pick([null, "uint8", "float"]),
    generic,
    metadata: random() < 0.2,
    bits: { POSITION: bits(1, 30), NORMAL: bits(2, 29), TEX_COORD: bits(1, 30), COLOR: bits(1, 30), GENERIC: bits(1, 30) },
    explicit: random() < 0.1 ? 8 + int(20) : 0,
    speed: c % 11,
    decodeSpeed: int(11),
    sequential: random() < 0.3,
  };
}

const valid = [];
async function encoded(group, geometry, settings) {
  let bytes;
  try {
    bytes = encode(geometry, settings);
  } catch {
    // The encoder aborts on some settings (normals quantized past ~20 bits), which ends its module.
    encoderModule = await draco3d.createEncoderModule({});
    bytes = null;
  }
  if (!bytes) {
    (stats["encoder refused"] ??= { cases: 0, identical: 0, refused: 0, capped: 0, aborted: 0, differ: 0 }).cases++;
    return;
  }
  const kind = settings.sequential ? "sequential" : `edgebreaker ${bytes[10] & 0x80 ? "" : bytes[11] === 2 ? "valence" : "standard"}`;
  const want = await compare(`${group} ${kind}`, bytes);
  if (want && bytes.length < 300000) valid.push(bytes);
}

for (let c = 0; c < CASES; c++) {
  const w = 1 + int(c < 4 ? 3 : 60), h = 1 + int(c < 4 ? 3 : 60);
  await encoded("grid", grid(w, h), randomSettings(c));
  await encoded("sphere", sphere(3 + int(40), 2 + int(30), false), randomSettings(c));
  await encoded("sphere seamed", sphere(3 + int(40), 2 + int(30), true), randomSettings(c));
  await encoded("soup", soup(1 + int(c < 4 ? 4 : 2000), 3 + int(c < 4 ? 6 : 1500)), randomSettings(c));
  await encoded("boxes", boxes(1 + int(40)), randomSettings(c));
}
// Every speed with each method on one mesh, normals and tex coords quantized.
for (let speed = 0; speed <= 10; speed++) {
  for (const sequential of [false, true]) {
    const settings = { ...randomSettings(speed), speed, decodeSpeed: speed, sequential, normals: "position", uv: true };
    settings.bits = { POSITION: 14, NORMAL: 10, TEX_COORD: 12, COLOR: 8, GENERIC: 8 };
    await encoded("every speed", sphere(24, 16, true), settings);
  }
}

// Draco's own test files (Apache License 2.0), bitstreams 2.0 to 2.2, fetched once and pinned.
const TESTDATA_URL = "https://raw.githubusercontent.com/google/draco/1.5.7/testdata/";
const TESTDATA = {
  "bunny_gltf.drc": "c1bf564f279849f311c4b4205dd16d729557c208fd9502ab124b784d146add80",
  "car.drc": "8c712644d842606223329ae3c8ce69d9d4ec9338a8e179b08486507bfa0f4101",
  "test_nm.obj.edgebreaker.1.0.0.drc": "43a7a9eba2d1ef2471ceb30e65c707f93f6dd7754f8d434b6cd32f0eda8c45b1",
  "test_nm.obj.edgebreaker.1.1.0.drc": "51f894188e5aac3a640dad7f6f9dfaf7830fb9e5a427daafe8363054780d472d",
  "test_nm.obj.edgebreaker.cl10.2.2.drc": "e0e0fb2a80227a93748fffdde4b8dc1c99455304b7fe0f16ef323b28810aa172",
  "test_nm.obj.edgebreaker.cl4.2.2.drc": "1ba8fc4eeacc513d89b430e39996cb5b863f8c04ed7cc7ecc10be898b482ae05",
  "test_nm.obj.sequential.1.0.0.drc": "edca54a0796f579900566da4b03ec57f0dd9f68f323103e77d041877e2ad9538",
  "test_nm.obj.sequential.1.1.0.drc": "987b1e6a9bc2f01562344aa57bf5ca90c7a4d4b3489b20fa9c894df4678c36b5",
};
const TESTDATA_DIR = path.join(ROOT, "bench/fixtures/draco");
let testdataFiles = 0;
for (const [name, sha256] of Object.entries(TESTDATA)) {
  const file = path.join(TESTDATA_DIR, name);
  let bytes = existsSync(file) ? new Uint8Array(await readFile(file)) : null;
  if (!bytes) {
    try {
      const res = await fetch(TESTDATA_URL + name);
      if (res.ok) bytes = new Uint8Array(await res.arrayBuffer());
    } catch {}
    if (!bytes) {
      console.log(`${name}: not fetched (set NODE_USE_ENV_PROXY=1 behind a proxy); skipped`);
      continue;
    }
  }
  if (createHash("sha256").update(bytes).digest("hex") !== sha256) throw new Error(`${name}: sha256 differs`);
  await mkdir(TESTDATA_DIR, { recursive: true });
  await writeFile(file, bytes);
  testdataFiles++;
  const want = await compare(`draco testdata 2.${bytes[6]}`, bytes);
  if (want) valid.push(bytes);
}

// PLATEAU's b3dm tiles: the glb after the 28-byte header and its tables, each primitive's
// KHR_draco_mesh_compression buffer view.
let plateauFiles = 0;
if (existsSync(PLATEAU)) {
  for (const name of (await readdir(PLATEAU)).filter((n) => n.endsWith(".b3dm")).sort()) {
    const b3dm = new Uint8Array(await readFile(path.join(PLATEAU, name)));
    const v = new DataView(b3dm.buffer, b3dm.byteOffset, b3dm.byteLength);
    const glbAt = 28 + v.getUint32(12, true) + v.getUint32(16, true) + v.getUint32(20, true) + v.getUint32(24, true);
    const jsonLength = v.getUint32(glbAt + 12, true);
    const gltf = JSON.parse(new TextDecoder().decode(b3dm.subarray(glbAt + 20, glbAt + 20 + jsonLength)));
    const binAt = glbAt + 20 + jsonLength + 8;
    plateauFiles++;
    for (const mesh of gltf.meshes ?? []) {
      for (const prim of mesh.primitives) {
        const ext = prim.extensions?.KHR_draco_mesh_compression;
        if (!ext) continue;
        const view = gltf.bufferViews[ext.bufferView];
        const bytes = b3dm.slice(binAt + (view.byteOffset ?? 0), binAt + (view.byteOffset ?? 0) + view.byteLength);
        const want = await compare("plateau", bytes);
        if (want && typeof want === "object") {
          for (const id of Object.values(ext.attributes)) if (!want.attributes.some((a) => a.uniqueId === id)) throw new Error(`${name}: no attribute ${id}`);
        }
        if (want) valid.push(bytes);
      }
    }
  }
}

// Truncated, corrupted and versioned copies, and garbage after a Draco header.
const pool = valid.filter((b) => b.length < 60000);
for (let c = 0; c < CASES * 40; c++) {
  const src = pick(pool);
  await compare("truncated", src.slice(0, int(src.length)));
  const flipped = src.slice();
  for (let n = 1 + int(4); n > 0; n--) flipped[int(flipped.length)] = int(256);
  await compare("corrupted", flipped);
  const bit = src.slice();
  const at = int(Math.min(bit.length, 64));
  bit[at] ^= 1 << int(8);
  await compare("corrupted header bit", bit);
  const longer = new Uint8Array(src.length + 1 + int(40)).map(() => int(256));
  longer.set(src);
  await compare("padded", longer);
}
for (const src of pool.slice(0, CASES * 4)) {
  for (const minor of [0, 1]) {
    const older = src.slice();
    older[6] = minor;
    await compare(`as version 2.${minor}`, older);
  }
}
for (let c = 0; c < CASES * 20; c++) {
  const garbage = new Uint8Array(11 + int(300)).map(() => int(256));
  garbage.set([68, 82, 65, 67, 79, 2, 2, 1, int(2), 0, 0]);
  if (garbage[8] === 1) garbage[11] = int(3);
  await compare("random after header", garbage);
}

const rows = Object.entries(stats).map(([group, r]) => ({ group, ...r }));
let total = 0, identical = 0, differ = 0, capped = 0;
for (const r of rows) {
  total += r.cases;
  identical += r.identical;
  differ += r.differ;
  capped += r.capped + r.aborted;
  console.log(`${r.group.padEnd(40)} ${String(r.cases).padStart(6)} cases, ${String(r.identical).padStart(6)} identical (${r.refused} refused by both), ${r.capped + r.aborted} past caps, ${r.differ} differ`);
}
console.log(`draco golden: ${total} cases, ${identical} identical (js and wasm-gc), ${capped} past the caps, ${differ} differ; ${plateauFiles} PLATEAU tiles, ${testdataFiles} Draco test files; ${restarts} draco3d restarts`);
for (const f of failures) console.log(`DIFF ${f.group}: ${f.bytes} bytes: want ${f.want}, js ${f.js}, wasm-gc ${f.wasm}`);
if (failures.length) await writeFile(path.join(ROOT, "bench/results/draco-golden-failures.json"), JSON.stringify(failures));
await writeFile(
  path.join(ROOT, "bench/results/draco-golden.json"),
  `${JSON.stringify({ env: { draco3d: "draco3d 1.5.7", node: process.version }, cases: CASES, total, identical, capped, differ, plateauFiles, testdataFiles, rows }, null, 2)}\n`,
);
if (differ > 0) process.exitCode = 1;
