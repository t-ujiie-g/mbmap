// meshopt (js and wasm-gc builds of bench/entry) vs meshoptimizer 1.3.0's MeshoptDecoder.decodeGltfBuffer:
// vertex streams encoded at every level and version, triangle lists and index sequences of both
// widths, filtered attributes of every filter and width, and truncated or corrupted copies of them.
// Output must be byte-identical, and the port must refuse exactly what meshoptimizer throws on.
// Usage: node meshopt/golden.mjs [--cases=N]; writes bench/results/meshopt-golden.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { MeshoptDecoder, MeshoptEncoder } from "meshoptimizer";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const CASES = Number(arg("cases", 40));
const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);
await MeshoptDecoder.ready;
await MeshoptEncoder.ready;

const MODES = ["ATTRIBUTES", "TRIANGLES", "INDICES"];
const FILTERS = ["NONE", "OCTAHEDRAL", "QUATERNION", "EXPONENTIAL", "COLOR"];

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

function reference(count, size, source, mode, filter) {
  const target = new Uint8Array(count * size);
  try {
    MeshoptDecoder.decodeGltfBuffer(target, count, size, source, mode, filter);
  } catch {
    return null;
  }
  return target;
}

function oursJs(count, size, source, mode, filter) {
  const target = new Uint8Array(count * size);
  return mbt.meshopt_decode(target, count, size, source, MODES.indexOf(mode), FILTERS.indexOf(filter)) ? target : null;
}

function oursGc(count, size, source, mode, filter) {
  const space = new Uint8Array(source.length + count * size);
  space.set(source);
  const addr = gc.copyIn(space);
  const out = addr + source.length;
  const ok = gc.exports.meshopt_decode_mem(addr, source.length, out, count, size, MODES.indexOf(mode), FILTERS.indexOf(filter));
  return ok ? new Uint8Array(gc.exports.memory.buffer, out, count * size).slice() : null;
}

// Exponential filters give NaN for an exponent of -128 times 0, whose bits differ by host (x86's
// default NaN has the sign set); the port writes 0x7fc00000. Such words compare as NaN.
let nanWords = 0;
function same(a, b, filter) {
  if (a === null || b === null) return a === b;
  if (a.length !== b.length) return false;
  if (filter !== "EXPONENTIAL") return a.every((v, i) => v === b[i]);
  const fa = new Float32Array(a.buffer, a.byteOffset, a.length / 4);
  const fb = new Float32Array(b.buffer, b.byteOffset, b.length / 4);
  const ua = new Uint32Array(a.buffer, a.byteOffset, a.length / 4);
  const ub = new Uint32Array(b.buffer, b.byteOffset, b.length / 4);
  return ua.every((v, i) => v === ub[i] || (Number.isNaN(fa[i]) && Number.isNaN(fb[i]) && ++nanWords > 0));
}

const stats = {};
const failures = [];
function compare(group, count, size, source, mode, filter = "NONE") {
  const s = (stats[group] ??= { cases: 0, identical: 0, refused: 0, differ: 0 });
  s.cases++;
  const want = reference(count, size, source, mode, filter);
  const js = oursJs(count, size, source, mode, filter);
  const wasm = oursGc(count, size, source, mode, filter);
  if (same(want, js, filter) && same(want, wasm, filter)) {
    s.identical++;
    if (want === null) s.refused++;
  } else {
    s.differ++;
    if (failures.length < 8) {
      const show = (r) => (r === null ? "refused" : `${r.length} bytes`);
      failures.push(`${group}: ${mode} ${filter} count ${count} size ${size} source ${source.length} bytes: want ${show(want)}, js ${show(js)}, wasm-gc ${show(wasm)}`);
    }
  }
  return want;
}

// Attribute data: smooth (slowly varying values of the element's width), noisy, sparse or constant.
function vertexData(count, size, kind) {
  const out = new Uint8Array(count * size);
  if (kind === "noise") {
    for (let i = 0; i < out.length; i++) out[i] = int(256);
  } else if (kind === "sparse") {
    for (let i = 0; i < out.length; i++) out[i] = random() < 0.05 ? int(256) : 0;
  } else if (kind === "constant") {
    for (let i = 0; i < size; i++) out[i] = int(256);
    for (let i = size; i < out.length; i++) out[i] = out[i - size];
  } else if (kind === "float") {
    const f = new Float32Array(out.buffer);
    const lanes = size / 4;
    for (let k = 0; k < lanes; k++) {
      let v = (random() - 0.5) * 1000, dv = random() - 0.5;
      for (let i = 0; i < count; i++) {
        f[i * lanes + k] = v;
        v += dv + (random() - 0.5) * 0.01;
      }
    }
  } else {
    const u = new Uint16Array(out.buffer);
    const lanes = size / 2;
    for (let k = 0; k < lanes; k++) {
      let v = int(65536);
      for (let i = 0; i < count; i++) {
        u[i * lanes + k] = v;
        v = (v + int(9) - 4) & 0xffff;
      }
    }
  }
  return out;
}

const valid = [];
const SIZES = [4, 8, 12, 16, 20, 24, 28, 32, 48, 64, 100, 128, 160, 192, 252, 256];
const COUNTS = [1, 2, 3, 15, 16, 17, 31, 255, 256, 257, 511, 1000];
for (let c = 0; c < CASES; c++) {
  for (const kind of ["smooth", "float", "noise", "sparse", "constant"]) {
    const size = pick(SIZES);
    const count = c < COUNTS.length ? COUNTS[c] : size <= 16 && random() < 0.3 ? 1 + int(70000) : 1 + int(Math.min(70000, (1 << 20) / size));
    const data = vertexData(count, size, kind);
    for (const version of [0, 1]) {
      for (let level = 0; level <= 3; level++) {
        if (version === 0 && level > 0) continue;
        const source = MeshoptEncoder.encodeVertexBufferLevel(data, count, size, level, version);
        const got = compare(`vertex v${version} level ${level}`, count, size, source, "ATTRIBUTES");
        if (got && !got.every((v, i) => v === data[i])) stats[`vertex v${version} level ${level}`].lossy = true;
        valid.push({ count, size, source, mode: "ATTRIBUTES" });
      }
    }
  }
}
for (const size of SIZES) {
  compare("vertex empty", 0, size, MeshoptEncoder.encodeVertexBufferLevel(new Uint8Array(0), 0, size, 2, 1), "ATTRIBUTES");
  compare("vertex empty", 0, size, MeshoptEncoder.encodeVertexBufferLevel(new Uint8Array(0), 0, size, 0, 0), "ATTRIBUTES");
}

// Triangle lists of a w x h grid, optionally with their triangles shuffled and corners rotated.
function grid(w, h, shuffle) {
  const tris = [];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * (w + 1) + x;
      tris.push([i, i + 1, i + w + 1], [i + 1, i + w + 2, i + w + 1]);
    }
  }
  if (shuffle) {
    for (let i = tris.length - 1; i > 0; i--) {
      const j = int(i + 1);
      [tris[i], tris[j]] = [tris[j], tris[i]];
    }
    for (const t of tris) for (let r = int(3); r > 0; r--) t.push(t.shift());
  }
  return new Uint32Array(tris.flat());
}

function indexBytes(indices, size) {
  return new Uint8Array((size === 2 ? new Uint16Array(indices) : new Uint32Array(indices)).buffer);
}

for (let c = 0; c < CASES; c++) {
  const w = 1 + int(c < 4 ? 3 : 200), h = 1 + int(c < 4 ? 3 : 200);
  for (const shuffle of [false, true]) {
    const tris = grid(w, h, shuffle);
    const size = (w + 1) * (h + 1) <= 65536 && random() < 0.6 ? 2 : 4;
    const bytes = indexBytes(tris, size);
    const triangles = MeshoptEncoder.encodeIndexBuffer(bytes, tris.length, size);
    compare(`triangles ${size * 8}-bit`, tris.length, size, triangles, "TRIANGLES");
    valid.push({ count: tris.length, size, source: triangles, mode: "TRIANGLES" });
    // v0 streams: the encoder only writes v1, so the header is rewritten (fec 13 and 14 then read the fifo)
    const v0 = triangles.slice();
    v0[0] = 0xe0;
    compare(`triangles v0 header`, tris.length, size, v0, "TRIANGLES");
    const reordered = tris.slice();
    MeshoptEncoder.reorderMesh(reordered, true, c % 2 === 0);
    const big = reordered.map((v) => v + (size === 4 ? 70000 + int(1 << 20) : 0));
    const optimized = MeshoptEncoder.encodeIndexBuffer(indexBytes(big, size), big.length, size);
    compare(`triangles reordered ${size * 8}-bit`, big.length, size, optimized, "TRIANGLES");
    valid.push({ count: big.length, size, source: optimized, mode: "TRIANGLES" });

    const strip = new Uint32Array(1 + int(5000)).map((_, i) => (size === 2 ? (i * 7 + int(50)) & 0xffff : i * 1000 + int(1 << 30)));
    const sequence = MeshoptEncoder.encodeIndexSequence(indexBytes(strip, size), strip.length, size);
    compare(`sequence ${size * 8}-bit`, strip.length, size, sequence, "INDICES");
    valid.push({ count: strip.length, size, source: sequence, mode: "INDICES" });
    const lines = tris.slice(0, 2 * Math.floor(tris.length / 2));
    const lineSequence = MeshoptEncoder.encodeIndexSequence(indexBytes(lines, size), lines.length, size);
    compare(`sequence ${size * 8}-bit`, lines.length, size, lineSequence, "INDICES");
  }
}
compare("triangles empty", 0, 2, MeshoptEncoder.encodeIndexBuffer(new Uint8Array(0), 0, 2), "TRIANGLES");
compare("sequence empty", 0, 4, MeshoptEncoder.encodeIndexSequence(new Uint8Array(0), 0, 4), "INDICES");

// Filtered attributes: unit normals, quaternions, floats of every magnitude and colors, encoded by
// the filter's encoder, then by the vertex codec; and random bytes under each filter.
function floats(count, lanes, kind) {
  const f = new Float32Array(count * lanes);
  for (let i = 0; i < count; i++) {
    const v = f.subarray(i * lanes, i * lanes + lanes);
    if (kind === "unit") {
      let l = 0;
      for (let k = 0; k < Math.min(lanes, 4); k++) l += (v[k] = random() * 2 - 1) ** 2;
      l = Math.sqrt(l) || 1;
      for (let k = 0; k < Math.min(lanes, 4); k++) v[k] /= l;
      if (random() < 0.05) v.fill(0, 0, 3);
      if (random() < 0.05) v.set([pick([-1, 0, 1]), pick([-1, 0, 1]), pick([-1, 0, 1])].map((x, k) => (k === 0 && x === 0 ? 1 : x)));
    } else if (kind === "color") {
      for (let k = 0; k < 4; k++) v[k] = random() < 0.1 ? pick([0, 1]) : random();
    } else {
      for (let k = 0; k < lanes; k++) v[k] = random() < 0.05 ? pick([0, -0, 1e-30, 1e30, -1]) : (random() - 0.5) * 10 ** (int(16) - 8);
    }
  }
  return f;
}

function filtered(group, count, size, bytes, filter) {
  const source = MeshoptEncoder.encodeVertexBuffer(bytes, count, size);
  compare(group, count, size, source, "ATTRIBUTES", filter);
  valid.push({ count, size, source, mode: "ATTRIBUTES", filter });
}

for (let c = 0; c < CASES; c++) {
  const count = c < COUNTS.length ? COUNTS[c] : 1 + int(5000);
  for (const stride of [4, 8]) {
    const bits = 2 + int(stride === 4 ? 7 : 15);
    filtered(`octahedral ${stride}`, count, stride, MeshoptEncoder.encodeFilterOct(floats(count, 4, "unit"), count, stride, bits), "OCTAHEDRAL");
    filtered(`color ${stride}`, count, stride, MeshoptEncoder.encodeFilterColor(floats(count, 4, "color"), count, stride, 2 + int(stride === 4 ? 7 : 15)), "COLOR");
    filtered(`octahedral ${stride} raw`, count, stride, vertexData(count, stride, "noise"), "OCTAHEDRAL");
    filtered(`color ${stride} raw`, count, stride, vertexData(count, stride, "noise"), "COLOR");
  }
  filtered("quaternion", count, 8, MeshoptEncoder.encodeFilterQuat(floats(count, 4, "unit"), count, 8, 4 + int(13)), "QUATERNION");
  filtered("quaternion raw", count, 8, vertexData(count, 8, "noise"), "QUATERNION");
  const lanes = 1 + int(8);
  for (const mode of ["Separate", "SharedVector", "SharedComponent", "Clamped"]) {
    const bytes = MeshoptEncoder.encodeFilterExp(floats(count, lanes, "any"), count, lanes * 4, 1 + int(24), mode);
    filtered(`exponential ${mode}`, count, lanes * 4, bytes, "EXPONENTIAL");
  }
  filtered("exponential raw", count, lanes * 4, vertexData(count, lanes * 4, "noise"), "EXPONENTIAL");
}

// Every value of the filters' inputs that steers them: octahedral x and y (z varied), quaternion
// scale words, exponent bytes (mantissa 0 included) and color alphas, other lanes random.
function lanes(count, size, fill) {
  const out = new Uint8Array(count * size);
  const view = new DataView(out.buffer);
  for (let i = 0; i < count; i++) fill(view, i * size, i);
  return out;
}
const s8 = () => int(256) - 128, s16 = () => int(65536) - 32768;
const zs8 = [0, 1, 64, 127, -128, -1];
filtered("octahedral 4 every x, y", 65536 * zs8.length, 4, lanes(65536 * zs8.length, 4, (v, o, i) => {
  v.setInt8(o, i & 0xff);
  v.setInt8(o + 1, (i >> 8) & 0xff);
  v.setInt8(o + 2, zs8[i >> 16]);
  v.setInt8(o + 3, s8());
}), "OCTAHEDRAL");
filtered("octahedral 8 every z", 65536, 8, lanes(65536, 8, (v, o, i) => {
  v.setInt16(o, random() < 0.1 ? 0 : s16(), true);
  v.setInt16(o + 2, random() < 0.1 ? 0 : s16(), true);
  v.setUint16(o + 4, i, true);
  v.setInt16(o + 6, s16(), true);
}), "OCTAHEDRAL");
filtered("quaternion every scale", 65536, 8, lanes(65536, 8, (v, o, i) => {
  for (let k = 0; k < 3; k++) v.setInt16(o + 2 * k, random() < 0.1 ? pick([0, 32767, -32768]) : s16(), true);
  v.setUint16(o + 6, i, true);
}), "QUATERNION");
filtered("exponential every exponent", 256 * 64, 4, lanes(256 * 64, 4, (v, o, i) => {
  v.setUint32(o, (((i >> 6) & 0xff) << 24) | (i & 63 ? int(1 << 24) : 0), true);
}), "EXPONENTIAL");
filtered("color 4 every alpha", 256 * 64, 4, lanes(256 * 64, 4, (v, o, i) => {
  v.setUint8(o, int(256));
  v.setInt8(o + 1, s8());
  v.setInt8(o + 2, s8());
  v.setUint8(o + 3, i >> 6);
}), "COLOR");
filtered("color 8 every alpha", 65536, 8, lanes(65536, 8, (v, o, i) => {
  v.setUint16(o, int(65536), true);
  v.setInt16(o + 2, s16(), true);
  v.setInt16(o + 4, s16(), true);
  v.setUint16(o + 6, i, true);
}), "COLOR");

// Truncated, corrupted and random inputs: the port must refuse exactly what meshoptimizer refuses.
const pool = valid.filter((v) => v.source.length < 200000);
for (let c = 0; c < CASES * 50; c++) {
  const v = pick(pool);
  const filter = v.filter ?? "NONE";
  const cut = v.source.slice(0, int(v.source.length));
  compare(`truncated ${v.mode.toLowerCase()}`, v.count, v.size, cut, v.mode, filter);
  const flipped = v.source.slice();
  for (let n = 1 + int(4); n > 0; n--) flipped[int(flipped.length)] = int(256);
  compare(`corrupted ${v.mode.toLowerCase()}`, v.count, v.size, flipped, v.mode, filter);
  const longer = new Uint8Array(v.source.length + 1 + int(40));
  longer.set(v.source);
  compare(`padded ${v.mode.toLowerCase()}`, v.count, v.size, longer, v.mode, filter);
  const step = v.mode === "TRIANGLES" ? 3 : 1;
  compare(`count off ${v.mode.toLowerCase()}`, Math.max(0, v.count + step * pick([-1, 1, 16, 256])), v.size, v.source, v.mode, filter);
}
for (let c = 0; c < CASES * 50; c++) {
  const mode = pick(MODES);
  const size = mode === "ATTRIBUTES" ? pick(SIZES) : pick([2, 4]);
  const count = mode === "TRIANGLES" ? 3 * int(30) : int(80);
  const garbage = new Uint8Array(int(400)).map(() => int(256));
  if (garbage.length) garbage[0] = pick([0xa0, 0xa1, 0xa2, 0xe0, 0xe1, 0xd0, 0xd1, int(256)]);
  compare(`random ${mode.toLowerCase()}`, Math.max(0, count), size, garbage, mode);
}

const rows = Object.entries(stats).map(([group, r]) => ({ group, ...r }));
let total = 0, identical = 0, differ = 0;
for (const r of rows) {
  total += r.cases;
  identical += r.identical;
  differ += r.differ;
  console.log(`${r.group.padEnd(34)} ${String(r.cases).padStart(6)} cases, ${String(r.identical).padStart(6)} identical (${r.refused} refused by both), ${r.differ} differ${r.lossy ? " LOSSY" : ""}`);
}
console.log(`meshopt golden: ${total} cases, ${identical} identical (js and wasm-gc), ${differ} differ; ${nanWords} exponential NaN words told apart only by their bits`);
for (const f of failures) console.log(`DIFF ${f}`);
await writeFile(
  path.join(ROOT, "bench/results/meshopt-golden.json"),
  `${JSON.stringify({ env: { meshoptimizer: "meshoptimizer 1.3.0", node: process.version }, cases: CASES, total, identical, differ, nanWords, rows }, null, 2)}\n`,
);
if (differ > 0 || rows.some((r) => r.lossy)) process.exitCode = 1;
