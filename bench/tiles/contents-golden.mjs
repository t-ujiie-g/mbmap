// mbmap/3d's i3dm and cmpt contents vs @loaders.gl/3d-tiles 4.5.4 on synthetic tiles, hostile ones
// refused; normals, which loaders.gl ignores or refuses, vs its own loop with Cesium's orientation.
// Usage: node tiles/contents-golden.mjs; writes bench/results/tiles-contents.json.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { parse } from "@loaders.gl/core";
import { Tiles3DLoader } from "@loaders.gl/3d-tiles";
import { octDecodeInRange } from "@loaders.gl/math";
import { Matrix3, Matrix4, Quaternion, Vector3 } from "@math.gl/core";
import { Ellipsoid } from "@math.gl/geospatial";
import { Document, NodeIO } from "@gltf-transform/core";
import { readTileContent } from "../../npm/src/tiles/content.ts";
import { ROOT } from "../lib/root.mjs";

// Mulberry32: the same tiles on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(7);

async function triangle() {
  const doc = new Document();
  const buf = doc.createBuffer();
  const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buf);
  const prim = doc.createPrimitive().setAttribute("POSITION", acc("VEC3", new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]))).setIndices(acc("SCALAR", new Uint16Array([0, 1, 2])));
  doc.createScene().addChild(doc.createNode().setMesh(doc.createMesh().addPrimitive(prim)));
  return new NodeIO().writeBinary(doc);
}
const GLB = await triangle();

const enc = (s) => new TextEncoder().encode(s);
const padText = (s) => s + " ".repeat((8 - (s.length % 8)) % 8);
const padBytes = (b) => {
  const out = new Uint8Array(b.length + ((8 - (b.length % 8)) % 8));
  out.set(b);
  return out;
};

/** A binary body of typed arrays, each 8-aligned; `refs` the feature table entries pointing at them. */
function body(fields) {
  const parts = [];
  const refs = {};
  let at = 0;
  for (const [name, array, componentType] of fields) {
    refs[name] = componentType ? { byteOffset: at, componentType } : { byteOffset: at };
    const bytes = padBytes(new Uint8Array(array.buffer, array.byteOffset, array.byteLength));
    parts.push(bytes);
    at += bytes.length;
  }
  const bin = new Uint8Array(at);
  let o = 0;
  for (const p of parts) bin.set(p, (o += p.length) - p.length);
  return { bin, refs };
}

function tile(magic, header, ft, ftBin, bt, btBin, rest) {
  const ftJson = enc(padText(JSON.stringify(ft)));
  const btJson = bt ? enc(padText(JSON.stringify(bt))) : new Uint8Array(0);
  const parts = [ftJson, ftBin, btJson, btBin, rest];
  const length = header + parts.reduce((a, p) => a + p.length, 0);
  const out = new Uint8Array(length + ((8 - (length % 8)) % 8));
  const v = new DataView(out.buffer);
  const words = [magic, 1, out.length, ftJson.length, ftBin.length, btJson.length, btBin.length];
  if (header === 32) words.push(rest.gltfFormat ?? 1);
  words.forEach((x, i) => v.setUint32(i * 4, x, true));
  let at = header;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

const I3DM = 0x6d643369;
const B3DM = 0x6d643362;
const CMPT = 0x74706d63;
const PNTS = 0x73746e70;

/** An i3dm of `fields` ([semantic, typed array, componentType?]) and global `json`, `gltf` embedded or a URI. */
function i3dm(fields, json, { uri, batch } = {}) {
  const { bin, refs } = body(fields);
  const rest = uri ? padBytes(enc(uri)) : GLB;
  rest.gltfFormat = uri ? 0 : 1;
  const bt = batch ? { name: batch } : null;
  return tile(I3DM, 32, { ...refs, ...json }, bin, bt, new Uint8Array(0), rest);
}

function b3dm(batchLength, rtc) {
  const ft = { BATCH_LENGTH: batchLength, ...(rtc ? { RTC_CENTER: rtc } : {}) };
  return tile(B3DM, 28, ft, new Uint8Array(0), { id: Array.from({ length: batchLength }, (_, i) => i * 10) }, new Uint8Array(0), GLB);
}

/** A pnts that ends where its tables do: loaders.gl goes on to the next tile from there, not from its byteLength. */
function pnts() {
  const { bin, refs } = body([["POSITION", new Float32Array([0, 0, 0, 1, 1, 1])]]);
  let ft = JSON.stringify({ POINTS_LENGTH: 2, ...refs });
  while ((28 + ft.length + bin.length) % 8) ft += " ";
  const out = new Uint8Array(28 + ft.length + bin.length);
  [PNTS, 1, out.length, ft.length, bin.length, 0, 0].forEach((x, i) => new DataView(out.buffer).setUint32(i * 4, x, true));
  out.set(enc(ft), 28);
  out.set(bin, 28 + ft.length);
  return out;
}

function cmpt(tiles) {
  const length = 16 + tiles.reduce((a, t) => a + t.length, 0);
  const out = new Uint8Array(length);
  const v = new DataView(out.buffer);
  [CMPT, 1, length, tiles.length].forEach((x, i) => v.setUint32(i * 4, x, true));
  let at = 16;
  for (const t of tiles) {
    out.set(t, at);
    at += t.length;
  }
  return out;
}

const f32 = (n, f) => Float32Array.from({ length: n }, f);
const TOKYO = [...Ellipsoid.WGS84.cartographicToCartesian([139.7671, 35.6812, 40])];
/** Whole meters near Tokyo, so they and their sum with an integral RTC_CENTER are exact in float32. */
const RTC = [-3959000, 3352000, 3697000];
const local = (n) => f32(3 * n, () => Math.round(200 * rand() - 100));
const unit = (n) => {
  const out = new Float32Array(3 * n);
  for (let i = 0; i < n; i++) {
    const a = 2 * Math.PI * rand();
    out.set([Math.cos(a), Math.sin(a), 0], 3 * i);
  }
  return out;
};
/** Ups at right angles to `unit`'s rights: their rotation of a quarter turn about z, tipped by z. */
const upsOf = (right) => {
  const out = new Float32Array(right.length);
  for (let i = 0; i < right.length; i += 3) out.set([-right[i + 1], right[i], 0], i);
  return out;
};
const octOf = (n) => Uint16Array.from({ length: 2 * n }, () => Math.floor(65536 * rand()));

const N = 24;
const ecefPositions = f32(3 * N, (_, i) => TOKYO[i % 3] + Math.round(400 * rand() - 200));
const rights = unit(N);
const cases = [
  ["float positions", i3dm([["POSITION", local(N)]], { INSTANCES_LENGTH: N })],
  ["quantized positions, offset and scale in JSON, SCALE", i3dm([["POSITION_QUANTIZED", Uint16Array.from({ length: 3 * N }, () => Math.floor(65536 * rand()))], ["SCALE", f32(N, () => 0.5 + 2 * rand())]], { INSTANCES_LENGTH: N, QUANTIZED_VOLUME_OFFSET: [-50.25, 10, 3.125], QUANTIZED_VOLUME_SCALE: [100.5, 20, 7] })],
  ["quantized positions, offset and scale in the binary", i3dm([["POSITION_QUANTIZED", Uint16Array.from({ length: 3 * N }, () => Math.floor(65536 * rand()))], ["QUANTIZED_VOLUME_OFFSET", new Float32Array([1.1, 2.2, 3.3])], ["QUANTIZED_VOLUME_SCALE", new Float32Array([9.9, 8.8, 7.7])]], { INSTANCES_LENGTH: N })],
  ["EAST_NORTH_UP, SCALE_NON_UNIFORM", i3dm([["POSITION", ecefPositions], ["SCALE_NON_UNIFORM", f32(3 * N, () => 0.25 + 3 * rand())]], { INSTANCES_LENGTH: N, EAST_NORTH_UP: true })],
  ["EAST_NORTH_UP, SCALE and SCALE_NON_UNIFORM", i3dm([["POSITION", ecefPositions], ["SCALE", f32(N, () => 0.5 + rand())], ["SCALE_NON_UNIFORM", f32(3 * N, () => 0.25 + 3 * rand())]], { INSTANCES_LENGTH: N, EAST_NORTH_UP: true })],
  ["BATCH_ID by default UNSIGNED_SHORT", i3dm([["POSITION", local(N)], ["BATCH_ID", Uint16Array.from({ length: N }, () => Math.floor(65536 * rand()))]], { INSTANCES_LENGTH: N }, { batch: Array(N).fill("x") })],
  ["BATCH_ID UNSIGNED_BYTE", i3dm([["POSITION", local(N)], ["BATCH_ID", Uint8Array.from({ length: N }, () => Math.floor(256 * rand())), "UNSIGNED_BYTE"]], { INSTANCES_LENGTH: N })],
  ["BATCH_ID UNSIGNED_SHORT", i3dm([["POSITION", local(N)], ["BATCH_ID", Uint16Array.from({ length: N }, (_, i) => N - i), "UNSIGNED_SHORT"]], { INSTANCES_LENGTH: N })],
  ["BATCH_ID UNSIGNED_INT", i3dm([["POSITION", local(N)], ["BATCH_ID", Uint32Array.from({ length: N }, () => Math.floor(4294967296 * rand())), "UNSIGNED_INT"]], { INSTANCES_LENGTH: N })],
  ["RTC_CENTER in JSON", i3dm([["POSITION", local(N)]], { INSTANCES_LENGTH: N, RTC_CENTER: RTC })],
  ["RTC_CENTER in the binary", i3dm([["POSITION", local(N)], ["RTC_CENTER", new Float32Array(RTC)]], { INSTANCES_LENGTH: N })],
  ["glTF by URI", i3dm([["POSITION", local(N)]], { INSTANCES_LENGTH: N }, { uri: "models/triangle.glb" })],
  ["no instances", i3dm([["POSITION", new Float32Array(0)]], { INSTANCES_LENGTH: 0 })],
];
// loaders.gl takes ENU at the position without RTC_CENTER, so the same instances with the center
// added to their (exact float32) positions are its answer for ours.
const rtcLocal = local(N);
const baked = f32(3 * N, (_, i) => rtcLocal[i] + RTC[i % 3]);
const bakedScales = f32(N, () => 1 + rand());
const bakedCases = [
  ["EAST_NORTH_UP with RTC_CENTER", i3dm([["POSITION", rtcLocal], ["SCALE", bakedScales]], { INSTANCES_LENGTH: N, EAST_NORTH_UP: true, RTC_CENTER: RTC }), i3dm([["POSITION", baked], ["SCALE", bakedScales]], { INSTANCES_LENGTH: N, EAST_NORTH_UP: true })],
];
const referenceCases = [
  ["NORMAL_UP and NORMAL_RIGHT", i3dm([["POSITION", local(N)], ["NORMAL_UP", upsOf(rights)], ["NORMAL_RIGHT", rights]], { INSTANCES_LENGTH: N })],
  ["NORMAL_UP_OCT32P and NORMAL_RIGHT_OCT32P, SCALE, RTC_CENTER", i3dm([["POSITION", local(N)], ["NORMAL_UP_OCT32P", octOf(N)], ["NORMAL_RIGHT_OCT32P", octOf(N)], ["SCALE", f32(N, () => 0.5 + rand())]], { INSTANCES_LENGTH: N, RTC_CENTER: RTC })],
];

/** loaders.gl's instance loop on its parsed tile, with Cesium's custom orientation and ENU at the position plus RTC_CENTER. */
function reference(ft, bin) {
  const n = ft.INSTANCES_LENGTH;
  const array = (name, Type, k) => (ft[name] ? new Type(bin.buffer, bin.byteOffset + ft[name].byteOffset, n * k) : null);
  const position = array("POSITION", Float32Array, 3);
  const up = array("NORMAL_UP", Float32Array, 3);
  const right = array("NORMAL_RIGHT", Float32Array, 3);
  const octUp = array("NORMAL_UP_OCT32P", Uint16Array, 2);
  const octRight = array("NORMAL_RIGHT_OCT32P", Uint16Array, 2);
  const scale = array("SCALE", Float32Array, 1);
  const nonUniform = array("SCALE_NON_UNIFORM", Float32Array, 3);
  const rtc = ft.RTC_CENTER ?? [0, 0, 0];
  const out = [];
  for (let i = 0; i < n; i++) {
    const p = new Vector3(position[3 * i], position[3 * i + 1], position[3 * i + 2]);
    const rotation = new Matrix3();
    const u = new Vector3();
    const r = new Vector3();
    if (up) {
      u.set(up[3 * i], up[3 * i + 1], up[3 * i + 2]);
      r.set(right[3 * i], right[3 * i + 1], right[3 * i + 2]);
    } else if (octUp) {
      octDecodeInRange(octUp[2 * i], octUp[2 * i + 1], 65535, u);
      octDecodeInRange(octRight[2 * i], octRight[2 * i + 1], 65535, r);
    } else if (ft.EAST_NORTH_UP) {
      new Matrix4(Ellipsoid.WGS84.eastNorthUpToFixedFrame(new Vector3(p).add(rtc))).getRotationMatrix3(rotation);
    }
    if (up || octUp) {
      const forward = new Vector3(r).cross(u).normalize();
      rotation.setColumn(0, r);
      rotation.setColumn(1, u);
      rotation.setColumn(2, forward);
    }
    const s = new Vector3(1, 1, 1);
    if (scale && Number.isFinite(scale[i])) s.multiplyByScalar(scale[i]);
    if (nonUniform) s.scale([nonUniform[3 * i], nonUniform[3 * i + 1], nonUniform[3 * i + 2]]);
    const m = new Matrix4().identity().translate(new Vector3(p).add(rtc)).multiplyRight(new Matrix4().fromQuaternion(new Quaternion().fromMatrix3(rotation))).scale(s);
    out.push(...m);
  }
  return out;
}

const sameNumbers = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const theirsOf = async (bytes) => parse(bytes, Tiles3DLoader, { "3d-tiles": { loadGLTF: false } });
const loads = [];
const load = async (uri) => {
  loads.push(uri);
  if (uri === "models/triangle.glb") return GLB;
  throw new Error(`no ${uri}`);
};
/** loaders.gl's matrices with RTC_CENTER added to their translation, and batch ids. */
function theirInstances(theirs) {
  const rtc = theirs.rtcCenter ? [...theirs.rtcCenter] : [0, 0, 0];
  return {
    matrices: theirs.instances.flatMap((x) => [...x.modelMatrix].map((v, k) => (k >= 12 && k < 15 ? v + rtc[k - 12] : v))),
    batchIds: theirs.instances.map((x) => x.batchId),
  };
}

const results = [];
let failed = 0;
const record = (r) => {
  if (!r.same) failed++;
  results.push(r);
};

for (const [name, bytes] of cases) {
  const theirs = await theirsOf(bytes);
  const ours = await readTileContent(bytes, load);
  const t = theirInstances(theirs);
  const ft = JSON.parse(new TextDecoder().decode(bytes.subarray(32, 32 + new DataView(bytes.buffer).getUint32(12, true))));
  const bin = bytes.subarray(32 + new DataView(bytes.buffer).getUint32(12, true)).subarray(0, new DataView(bytes.buffer).getUint32(16, true));
  const ref = "POSITION_QUANTIZED" in ft || (ft.RTC_CENTER && !Array.isArray(ft.RTC_CENTER)) ? null : reference(ft, bin);
  const model = theirs.gltfUrl ? loads.includes(theirs.gltfUrl) && ours.model.primitives.length === 1 : ours.model.primitives.length === 1;
  const same = ours.kind === "i3dm" && sameNumbers([...ours.instances.matrices], t.matrices) && sameNumbers([...ours.instances.batchIds], t.batchIds) && ours.batchLength === t.batchIds.length && (!ref || sameNumbers(ref, t.matrices)) && model;
  record({ case: name, against: "loaders.gl", instances: t.batchIds.length, same, ...(ref ? { referenceMatchesLoaders: sameNumbers(ref, t.matrices) } : {}) });
}
for (const [name, bytes, bakedBytes] of bakedCases) {
  const t = theirInstances(await theirsOf(bakedBytes));
  const ours = await readTileContent(bytes, load);
  record({ case: name, against: "loaders.gl on positions with RTC_CENTER added", instances: t.batchIds.length, same: sameNumbers([...ours.instances.matrices], t.matrices) });
}
for (const [name, bytes] of referenceCases) {
  const v = new DataView(bytes.buffer);
  const ftLength = v.getUint32(12, true);
  const ft = JSON.parse(new TextDecoder().decode(bytes.subarray(32, 32 + ftLength)));
  const ours = await readTileContent(bytes, load);
  const ref = reference(ft, bytes.subarray(32 + ftLength, 32 + ftLength + v.getUint32(16, true)));
  record({ case: name, against: "reference (loaders.gl's loop with Cesium's orientation)", instances: ft.INSTANCES_LENGTH, same: sameNumbers([...ours.instances.matrices], ref) });
}

/** loaders.gl's inner tiles in order, nested cmpts flattened, pnts counted apart. */
function flatten(theirs, out = { parts: [], skipped: 0 }) {
  for (const t of theirs.tiles) {
    if (t.type === "cmpt") flatten(t, out);
    else if (t.type === "pnts") out.skipped++;
    else out.parts.push(t);
  }
  return out;
}
// loaders.gl reads a nested cmpt's tiles only while its byteLength exceeds their offset in the outer
// one, so a nested cmpt after others would read as empty there.
const composites = [
  ["b3dm and i3dm", cmpt([b3dm(3, [1, 2, 3]), cases[3][1]])],
  ["nested cmpts", cmpt([cmpt([b3dm(2), cmpt([cases[9][1], cases[5][1]])]), cases[0][1], b3dm(5, RTC)])],
  ["with pnts", cmpt([cmpt([pnts()]), pnts(), cases[1][1]])],
];
for (const [name, bytes] of composites) {
  const theirs = flatten(await theirsOf(bytes));
  const ours = await readTileContent(bytes, load);
  let same = ours.kind === "cmpt" && ours.parts.length === theirs.parts.length && ours.skipped === theirs.skipped && ours.model.primitives.length === 0;
  for (const [i, t] of theirs.parts.entries()) {
    const o = ours.parts[i];
    if (!same || o.kind !== t.type) {
      same = false;
      break;
    }
    if (t.type === "b3dm") {
      same &&= o.batchLength === t.featureTableJson.BATCH_LENGTH && JSON.stringify(o.rtc) === JSON.stringify(t.rtcCenter ? [...t.rtcCenter] : null) && JSON.stringify(o.batchTable) === JSON.stringify(t.batchTableJson) && o.model.primitives.length === 1;
    } else {
      const ti = theirInstances(t);
      same &&= sameNumbers([...o.instances.matrices], ti.matrices) && sameNumbers([...o.instances.batchIds], ti.batchIds);
    }
  }
  record({ case: `cmpt: ${name}`, against: "loaders.gl", parts: theirs.parts.map((t) => t.type).join(","), skipped: theirs.skipped, same });
}

// Hostile files: each must be refused with an Error, never read past its buffer or hang.
const good = cases[1][1];
const withWord = (bytes, at, value) => {
  const out = bytes.slice();
  new DataView(out.buffer).setUint32(at, value, true);
  return out;
};
let deep = b3dm(1);
for (let i = 0; i < 12; i++) deep = cmpt([deep]);
const hostile = [
  ["i3dm cut short", good.subarray(0, 40)],
  ["i3dm header cut short", good.subarray(0, 20)],
  ["i3dm byteLength past the file", withWord(good, 8, good.length + 8)],
  ["i3dm feature table past the file", withWord(good, 16, 1 << 24)],
  ["i3dm version 2", withWord(good, 4, 2)],
  ["i3dm gltfFormat 2", withWord(good, 28, 2)],
  ["INSTANCES_LENGTH absurd", i3dm([["POSITION", local(1)]], { INSTANCES_LENGTH: 1e9 })],
  ["INSTANCES_LENGTH past POSITION", i3dm([["POSITION", local(2)]], { INSTANCES_LENGTH: 3 })],
  ["INSTANCES_LENGTH missing", i3dm([["POSITION", local(2)]], {})],
  ["POSITION byteOffset past the binary", i3dm([["POSITION", local(1)]], { INSTANCES_LENGTH: 1, POSITION: { byteOffset: 1 << 20 } })],
  ["POSITION_QUANTIZED without its volume", i3dm([["POSITION_QUANTIZED", new Uint16Array(3)]], { INSTANCES_LENGTH: 1 })],
  ["no position", i3dm([["SCALE", new Float32Array(1)]], { INSTANCES_LENGTH: 1 })],
  ["NORMAL_UP without NORMAL_RIGHT", i3dm([["POSITION", local(1)], ["NORMAL_UP", new Float32Array(3)]], { INSTANCES_LENGTH: 1 })],
  ["BATCH_ID of an unknown componentType", i3dm([["POSITION", local(1)], ["BATCH_ID", new Uint16Array(1), "HALF"]], { INSTANCES_LENGTH: 1 })],
  ["feature table JSON null", tile(I3DM, 32, null, new Uint8Array(0), null, new Uint8Array(0), GLB)],
  ["i3dm without its glTF", i3dm([["POSITION", local(1)]], { INSTANCES_LENGTH: 1 }).subarray(0, 32 + 48)],
  ["cmpt nested 12 deep", deep],
  ["cmpt inner byteLength 0", withWord(cmpt([b3dm(1)]), 16 + 8, 0)],
  ["cmpt inner byteLength past the file", withWord(cmpt([b3dm(1)]), 16 + 8, 1 << 20)],
  ["cmpt tilesLength past its tiles", withWord(cmpt([b3dm(1)]), 12, 1000)],
  ["cmpt tilesLength absurd", withWord(cmpt([b3dm(1)]), 12, 0xffffffff)],
  ["cmpt cut short", cmpt([b3dm(1)]).subarray(0, 100)],
  ["cmpt of an unknown tile", withWord(cmpt([b3dm(1)]), 16, 0x12345678)],
];
for (const [name, bytes] of hostile) {
  let refused = null;
  try {
    await readTileContent(bytes, load);
  } catch (err) {
    refused = err instanceof Error ? err.message : String(err);
  }
  record({ case: `hostile: ${name}`, same: refused !== null, refused });
}

await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/tiles-contents.json"), JSON.stringify({ env: { loaders: "@loaders.gl/3d-tiles 4.5.4" }, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
console.log(`tiles contents golden: ${results.length - failed} of ${results.length} the same`);
if (failed) process.exit(1);
