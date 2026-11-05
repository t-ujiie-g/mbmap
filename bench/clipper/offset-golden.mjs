// clipper's offsetting vs Clipper2 2.0.1's InflatePaths (clipper2-wasm 0.4.0): every join and
// end type it exposes, growing and shrinking, miter limits and arc tolerances; must be identical.
// Usage: node clipper/offset-golden.mjs [--cases=N]
import Clipper2Z from "clipper2-wasm/dist/es/clipper2z.js";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { arg } from "../lib/args.mjs";

const CASES = Number(arg("cases", 300));
const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);
const C = await Clipper2Z();

function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const toPaths = (paths) => {
  const out = new C.Paths64();
  for (const p of paths) {
    const path = new C.Path64();
    const xyz = new BigInt64Array(p.length * 3);
    p.forEach(([x, y], i) => { xyz[i * 3] = BigInt(x); xyz[i * 3 + 1] = BigInt(y); });
    path.assign(xyz);
    out.push_back(path);
    path.delete();
  }
  return out;
};
const JOINS = { 0: C.JoinType.Square, 2: C.JoinType.Round, 3: C.JoinType.Miter };
const ENDS = [C.EndType.Polygon, C.EndType.Joined, C.EndType.Butt, C.EndType.Square, C.EndType.Round];
function reference(paths, delta, join, end, miter, arc) {
  const input = toPaths(paths);
  const r = C.InflatePaths64(input, delta, JOINS[join], ENDS[end], miter, arc);
  const out = [r.size()];
  for (let i = 0; i < r.size(); i++) {
    const v = r.get(i).view();
    out.push(v.length / 3);
    for (let k = 0; k < v.length; k += 3) out.push(Number(v[k]), Number(v[k + 1]));
  }
  input.delete();
  r.delete();
  return out;
}
const encode = (paths) => {
  const words = [paths.length];
  for (const p of paths) {
    words.push(p.length);
    for (const [x, y] of p) words.push(x, y);
  }
  return new Uint8Array(new Int32Array(words).buffer);
};
const hash = (words) => {
  let h = 0x811c9dc5 | 0;
  for (const v of words) h = Math.imul(h ^ v, 0x01000193);
  return h;
};

const r = rng(777);
const poly = (range, k) => Array.from({ length: k }, () => [Math.floor((r() - 0.5) * range), Math.floor((r() - 0.5) * range)]);
const cases = [];
for (let i = 0; i < CASES; i++) {
  const range = [100, 10000, 1e6][i % 3];
  const kind = i % 4;
  const paths = kind === 0 ? [poly(range, 3 + Math.floor(r() * 8))]
    : kind === 1 ? Array.from({ length: 1 + Math.floor(r() * 3) }, () => poly(range, 3 + Math.floor(r() * 6)))
    : kind === 2 ? [poly(range, 2 + Math.floor(r() * 6))]
    : [poly(range, 1)];
  const delta = (r() < 0.25 ? -1 : 1) * range * (0.01 + r() * 0.2);
  const miter = r() < 0.5 ? 2 : 1 + r() * 4;
  const arc = r() < 0.5 ? 0 : range * r() * 0.01;
  cases.push({ name: `case ${i} (range ${range})`, paths, delta, miter, arc });
}

let runs = 0, same = 0, sameGc = 0;
const failures = [];
for (const c of cases) {
  const input = encode(c.paths);
  const addr = gc.copyIn(input);
  for (const join of [0, 2, 3]) {
    for (let end = 0; end < 5; end++) {
      runs++;
      const ref = reference(c.paths, c.delta, join, end, c.miter, c.arc);
      const got = mbt.offset_bytes(input, c.delta, join, end, c.miter, c.arc);
      if (got === ref.join(",")) same++;
      else if (failures.length < 5) failures.push(`${c.name} join ${join} end ${end} delta ${c.delta}:\n  ref ${ref.slice(0, 30).join(",")}\n  got ${got.slice(0, 150)}`);
      if (gc.exports.offset_hash_mem(addr, input.length, c.delta, join, end, c.miter, c.arc) === hash(ref)) sameGc++;
    }
  }
}
console.log(`offset golden: ${runs} runs over ${cases.length} cases; js identical ${same}, wasm-gc identical ${sameGc}`);
for (const f of failures) console.log(f);
if (same !== runs || sameGc !== runs) process.exitCode = 1;
