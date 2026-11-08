// lepcc (js and wasm-gc builds) vs Esri's LEPCC C++ (bench/lepcc/upstream.mjs) on blobs its encoder writes, the
// pack test's point cloud layer and hostile copies: bitwise identical or refused by both, else refused where the
// C++ goes out of bounds (ASan), leaves points unwritten or passes the caps. Usage: node lepcc/golden.mjs [--cases=N]
import { existsSync, readFileSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { ENTRY_JS } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { writeInput } from "../../wasmio/js/host.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";
import { COMMIT, KINDS, buildUpstream, decodeUpstream, encodeIntensity, encodeRgb, encodeXyz } from "./upstream.mjs";

const CASES = Number(arg("cases", 6));
const MODEL_WASM = "_build/wasm-gc/release/build/model_worker/model_worker.wasm";
const MAX_POINTS = 0x400000;
const EACH = [24, 3, 2];

await buildUpstream();
const mbt = await nodeImportJs(ENTRY_JS);
const { instance } = await WebAssembly.instantiate(await nodeFetchBytes(MODEL_WASM), {});
const gc = instance.exports;

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
const gauss = () => Math.sqrt(-2 * Math.log(1 - random())) * Math.cos(2 * Math.PI * random());

/** The port's "LEPCC output" as `{count, values}`, or null when refused; throws past a trap. */
function ours(which, kind, blob) {
  const k = KINDS.indexOf(kind);
  let out;
  if (which === "js") {
    out = mbt.lepcc_decode(k, blob);
    if (out.length === 0) return null;
  } else {
    writeInput(gc, [blob], "LEPCC data");
    const n = gc.lepcc_decode(k);
    if (n === -1) return null;
    if (n < 0) throw new Error(`lepcc_decode ${n}`);
    out = new Uint8Array(gc.memory.buffer.slice(gc.output_addr(), gc.output_addr() + n));
  }
  const count = new DataView(out.buffer, out.byteOffset, 8).getUint32(0, true);
  if (out.length !== 8 + count * EACH[k]) throw new Error("malformed output");
  return { count, values: out.subarray(8) };
}

const stats = {};
let slowest = 0;
const failures = [];
const sameBytes = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

/** Compares a batch of `{group, kind, blob}` with the C++ (`asan`: its build with AddressSanitizer). */
function compareAll(records, asan) {
  const results = decodeUpstream(records, { asan });
  records.forEach((r, i) => compare(r, results[i]));
}

function compare({ group, kind, blob }, want) {
  const s = (stats[group] ??= { cases: 0, identical: 0, refused: 0, overread: 0, unfilled: 0, capped: 0, differ: 0, points: 0 });
  s.cases++;
  const got = {};
  for (const which of ["js", "wasm-gc"]) {
    const t = performance.now();
    try {
      got[which] = ours(which, kind, blob);
    } catch (e) {
      got[which] = `threw ${e.message}`;
    }
    slowest = Math.max(slowest, performance.now() - t);
  }
  const verdict = (() => {
    const refused = got.js === null && got["wasm-gc"] === null;
    if (want.crashed) return refused ? "overread" : "differ";
    if (want.status === -1) return refused ? "capped" : "differ";
    if (want.status !== 0 || want.countStatus !== 0) return refused ? "refused" : "differ";
    if (want.unfilled > 0) return refused ? "unfilled" : "differ";
    const bytes = new Uint8Array(want.values.buffer, want.values.byteOffset, want.values.byteLength);
    for (const which of ["js", "wasm-gc"]) {
      const g = got[which];
      if (!g || typeof g === "string" || g.count !== want.count || !sameBytes(g.values, bytes)) return "differ";
    }
    s.points += want.count;
    return "identical";
  })();
  if (verdict === "refused") s.identical++;
  s[verdict]++;
  if (verdict === "differ") {
    const show = (g) => (g === null ? "refused" : typeof g === "string" ? g : `${g.count} values`);
    failures.push({ group, kind, bytes: blob.length, want: want.crashed ? "C++ overreads" : want.status ? `status ${want.status}` : `${want.count} values`, js: show(got.js), wasm: show(got["wasm-gc"]) });
  }
}

// Point sets: [name, points (interleaved x, y, z), maxX, maxY, maxZ].
const TOKYO = [139.7671, 35.6812];
function points(n, f) {
  const out = new Float64Array(n * 3);
  for (let i = 0; i < n; i++) out.set(f(i), i * 3);
  return out;
}
const sets = [];
for (let c = 0; c < CASES; c++) {
  const deg = 1e-8 * (1 + int(100));
  const z = 0.001 * (1 + int(50));
  sets.push(
    ["one point", points(1, () => [TOKYO[0] + random(), TOKYO[1] + random(), 40 * random()]), deg, deg, z],
    ["small", points(2 + int(30), () => [TOKYO[0] + random() * 1e-3, TOKYO[1] + random() * 1e-3, 40 * random()]), deg, deg, z],
    ["flat", points(1000 + int(3000), () => [TOKYO[0] + random() * 2e-3, TOKYO[1] + random() * 2e-3, 3.25]), deg, deg, z],
    ["clustered", points(5000 + int(5000), (i) => {
      const k = i % 7;
      return [TOKYO[0] + k * 1e-4 + gauss() * 1e-6, TOKYO[1] - k * 1e-4 + gauss() * 1e-6, 10 * k + gauss()];
    }), deg, deg, z],
    ["duplicates", points(500, (i) => [TOKYO[0] + (i % 5) * 1e-5, TOKYO[1], 2 + (i % 3)]), deg, deg, z],
    ["grid", points(4096, (i) => [TOKYO[0] + (i % 64) * 1e-6, TOKYO[1] + Math.floor(i / 64) * 1e-6, ((i * 37) % 101) * 0.1]), 5e-7, 5e-7, 0.05],
    ["ECEF meters", points(2000 + int(4000), () => [-3959000 + random() * 500, 3352000 + random() * 500, 3697000 + random() * 500]), 0.001 * (1 + int(10)), 0.001 * (1 + int(10)), z],
    ["projected meters", points(2000 + int(4000), () => [-5000 + random() * 800, -36000 + random() * 800, 30 + random() * 200]), 0.005, 0.005, 0.01 * (1 + int(5))],
    ["UTM meters", points(3000, () => [386000 + random() * 1000, 3949000 + random() * 1000, random() * 3776]), 0.01, 0.01, 0.01],
    ["coarse error", points(3000, () => [random() * 1000, random() * 1000, random() * 100]), 1 + int(5), 1 + int(5), 0.5],
  );
}
sets.push(["100k points", points(100000, () => [TOKYO[0] + random() * 5e-3, TOKYO[1] + random() * 5e-3, 40 * random() + gauss()]), 1e-8, 1e-8, 0.005]);
sets.push(["100k points", points(100000, () => [-3959000 + random() * 300, 3352000 + random() * 300, 3697000 + random() * 300]), 0.002, 0.002, 0.002]);

// Colors and intensities.
const rgbs = [];
const intensities = [];
for (let c = 0; c < CASES; c++) {
  const n = 100 + int(20000);
  const palette = (k) => Array.from({ length: k }, () => [int(256), int(256), int(256)]);
  for (const [name, colors] of [["one color", palette(1)], ["two colors", palette(2)], ["few colors", palette(2 + int(20))], ["256 colors", palette(256)]]) {
    const rgb = new Uint8Array(n * 3);
    for (let i = 0; i < n; i++) rgb.set(colors[int(colors.length)], i * 3);
    rgbs.push([name, rgb]);
  }
  rgbs.push(["many colors", new Uint8Array(n * 3).map(() => int(256))]);
  rgbs.push(["raw (few points)", new Uint8Array((1 + int(40)) * 3).map(() => int(256))]);
  const gradient = new Uint8Array(n * 3);
  for (let i = 0; i < n; i++) gradient.set([i % 256, (i >> 2) % 256, 255 - (i % 256)], i * 3);
  rgbs.push(["gradient", gradient]);
  for (const [name, f] of [
    ["8-bit", () => int(256)],
    ["16-bit", () => int(65536)],
    ["12-bit", () => int(4096)],
    ["upscaled by 256", () => int(256) * 256],
    ["upscaled by 3", () => int(1000) * 3],
    ["constant", () => 777],
    ["zeros", () => 0],
    ["0 or 1", () => int(2)],
    ["below 128", () => int(128)],
  ]) intensities.push([name, Uint16Array.from({ length: 1 + int(20000) }, f)]);
}

const valid = [];
for (const [name, xyz, mx, my, mz] of sets) valid.push({ group: `xyz ${name}`, kind: "xyz", blob: encodeXyz(xyz, mx, my, mz).blob });
for (const [name, rgb] of rgbs) valid.push({ group: `rgb ${name}`, kind: "rgb", blob: encodeRgb(rgb) });
for (const [name, v] of intensities) valid.push({ group: `intensity ${name}`, kind: "intensity", blob: encodeIntensity(v) });
// The pack test's synthetic point cloud layer (bench/i3s/pcsl-synthetic.mjs), as committed.
const PCSL = path.join(ROOT, "bench/npm/pages/i3s/pcsl/layers/0/nodes");
for (let id = 0; existsSync(path.join(PCSL, String(id))); id++) {
  const file = (rel) => new Uint8Array(readFileSync(path.join(PCSL, String(id), rel)));
  valid.push({ group: "pcsl synthetic layer", kind: "xyz", blob: file("geometries/0") });
  valid.push({ group: "pcsl synthetic layer", kind: "rgb", blob: file("attributes/4/0") });
  valid.push({ group: "pcsl synthetic layer", kind: "intensity", blob: file("attributes/2/0") });
}
compareAll(valid, false);

// Hostile copies of the smaller blobs.
function fletcher32(b, start, len) {
  let sum1 = 0xffff, sum2 = 0xffff, words = Math.floor(len / 2), p = start;
  while (words) {
    let t = Math.min(words, 359);
    words -= t;
    do {
      sum1 = (sum1 + (b[p++] << 8)) >>> 0;
      sum1 = (sum1 + b[p++]) >>> 0;
      sum2 = (sum2 + sum1) >>> 0;
    } while (--t);
    sum1 = (sum1 & 0xffff) + (sum1 >>> 16);
    sum2 = (sum2 & 0xffff) + (sum2 >>> 16);
  }
  if (len & 1) {
    sum1 = (sum1 + (b[p] << 8)) >>> 0;
    sum2 = (sum2 + sum1) >>> 0;
  }
  sum1 = (sum1 & 0xffff) + (sum1 >>> 16);
  sum2 = (sum2 & 0xffff) + (sum2 >>> 16);
  return ((sum2 << 16) | sum1) >>> 0;
}
/** Rewrites the checksum over the blob size its header gives (where that fits the copy). */
function reseal(b) {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const size = Number(v.getBigInt64(16, true));
  if (size >= 16 && size <= b.length) v.setUint32(12, fletcher32(b, 16, size - 16), true);
  return b;
}
const COUNT_AT = { xyz: 96, rgb: 24, intensity: 24 };
const HEADER = { xyz: 104, rgb: 32, intensity: 32 };
const hostile = [];
// Seeds of the hostile copies: each group's first two blobs under 8000 bytes.
const seeds = {};
const small = valid.filter((r) => r.blob.length < 8000 && (seeds[r.group] = (seeds[r.group] ?? 0) + 1) <= 2);
for (const { group, kind, blob } of small) {
  const g = (what) => `hostile ${kind}: ${what}`;
  for (const n of [0, 10, 24, HEADER[kind] - 1, HEADER[kind], HEADER[kind] + 1, blob.length >> 1, blob.length - 1]) {
    if (n >= 0 && n < blob.length) hostile.push({ group: g("truncated"), kind, blob: blob.slice(0, n) });
  }
  for (let k = 0; k < 6; k++) {
    const b = blob.slice();
    b[int(b.length)] ^= 1 << int(8);
    hostile.push({ group: g("bit flipped"), kind, blob: b });
  }
  for (let k = 0; k < 12; k++) {
    const b = blob.slice();
    const at = HEADER[kind] + int(Math.max(1, b.length - HEADER[kind]));
    if (at < b.length) b[at] ^= 1 << int(8);
    hostile.push({ group: g("payload bit flipped, resealed"), kind, blob: reseal(b) });
  }
  for (let k = 0; k < 3; k++) {
    const b = blob.slice();
    const at = 24 + int(HEADER[kind] - 24);
    b[at] = int(256);
    hostile.push({ group: g("header byte rewritten, resealed"), kind, blob: reseal(b) });
  }
  const view = (b) => new DataView(b.buffer, b.byteOffset, b.byteLength);
  const count = view(blob).getUint32(COUNT_AT[kind], true);
  for (const c of [0, 1, count - 1, count + 1, MAX_POINTS, MAX_POINTS + 1, 0x7fffffff, 0xffffffff]) {
    const b = blob.slice();
    view(b).setUint32(COUNT_AT[kind], c >>> 0, true);
    hostile.push({ group: g("count rewritten, resealed"), kind, blob: reseal(b) });
  }
  for (const s of [0n, 15n, 16n, BigInt(HEADER[kind] - 1), BigInt(blob.length - 1), BigInt(blob.length + 1), 1n << 40n, -1n]) {
    const b = blob.slice();
    view(b).setBigInt64(16, s, true);
    hostile.push({ group: g("blob size rewritten"), kind, blob: s >= 16n && s <= BigInt(b.length) ? reseal(b) : b });
  }
  const newer = blob.slice();
  newer[10] = 2;
  hostile.push({ group: g("newer version"), kind, blob: newer });
  const longer = new Uint8Array(blob.length + 1 + int(40)).map(() => int(256));
  longer.set(blob);
  hostile.push({ group: g("trailing bytes"), kind, blob: longer });
  const other = KINDS[(KINDS.indexOf(kind) + 1) % 3];
  hostile.push({ group: g(`decoded as ${other}`), kind: other, blob });
  void group;
}
const started = performance.now();
compareAll(hostile, true);
const hostileMs = performance.now() - started;

const rows = Object.entries(stats).map(([group, r]) => ({ group, ...r }));
let total = 0, identical = 0, differ = 0, overread = 0, unfilled = 0, capped = 0;
for (const r of rows) {
  total += r.cases;
  identical += r.identical;
  differ += r.differ;
  overread += r.overread;
  unfilled += r.unfilled;
  capped += r.capped;
  console.log(`${r.group.padEnd(48)} ${String(r.cases).padStart(5)} cases, ${String(r.identical).padStart(5)} identical (${r.refused} refused by both; ${r.points} values), ${r.overread} C++ out of bounds, ${r.unfilled} unwritten, ${r.capped} past caps, ${r.differ} differ`);
}
console.log(`lepcc golden (Esri/lepcc ${COMMIT.slice(0, 7)}): ${total} cases, ${identical} identical (js and wasm-gc), ${overread} where the C++ reads or writes out of bounds, ${unfilled} where it leaves points unwritten, ${capped} past the caps (all refused by the port), ${differ} differ; hostile copies in ${Math.round(hostileMs)} ms, the port's slowest decode ${slowest.toFixed(1)} ms`);
for (const f of failures.slice(0, 30)) console.log(`DIFF ${f.group}: ${f.bytes} bytes: want ${f.want}, js ${f.js}, wasm-gc ${f.wasm}`);
await writeFile(
  path.join(ROOT, "bench/results/lepcc-golden.json"),
  `${JSON.stringify({ env: { lepcc: `Esri/lepcc ${COMMIT}`, compiler: "g++ -O2 -ffp-contract=off (hostile copies with -fsanitize=address)", node: process.version }, cases: CASES, slowestMs: Math.round(slowest), total, identical, overread, unfilled, capped, differ, rows }, null, 2)}\n`,
);
if (differ > 0) process.exitCode = 1;
