// clipper vs Clipper2 2.0.1 (clipper2-wasm 0.4.0): random and grid polygons, open paths and GSI
// features under every ClipType and FillRule, as paths and trees; must be identical.
// Usage: node clipper/golden.mjs [--cases=N]
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import Clipper2Z from "clipper2-wasm/dist/es/clipper2z.js";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const CASES = Number(arg("cases", 300));
const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);
const C = await Clipper2Z();

// Mulberry32: the same cases on every run.
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
    for (let i = 0; i < p.length; i++) {
      xyz[i * 3] = BigInt(p[i][0]);
      xyz[i * 3 + 1] = BigInt(p[i][1]);
    }
    path.assign(xyz);
    out.push_back(path);
    path.delete();
  }
  return out;
};
const flattenRef = (paths, out) => {
  out.push(paths.size());
  for (let i = 0; i < paths.size(); i++) {
    const v = paths.get(i).view();
    out.push(v.length / 3);
    for (let k = 0; k < v.length; k += 3) out.push(Number(v[k]), Number(v[k + 1]));
  }
};
const CLIP_TYPES = [C.ClipType.Intersection, C.ClipType.Union, C.ClipType.Difference, C.ClipType.Xor];
const FILL_RULES = [C.FillRule.EvenOdd, C.FillRule.NonZero, C.FillRule.Positive, C.FillRule.Negative];

// The tree in preorder: each node's child count, then per child its polygon
// and subtree.
const flattenTree = (node, out) => {
  out.push(node.count());
  for (let i = 0; i < node.count(); i++) {
    const child = node.child(i);
    const v = child.polygon().view();
    out.push(v.length / 3);
    for (let k = 0; k < v.length; k += 3) out.push(Number(v[k]), Number(v[k + 1]));
    flattenTree(child, out);
  }
};

function reference({ subjects, open, clips }, op, fill, tree) {
  const c = new C.Clipper64();
  const [s, o, k] = [toPaths(subjects), toPaths(open), toPaths(clips)];
  c.AddSubject(s);
  c.AddOpenSubject(o);
  c.AddClip(k);
  const closed = tree ? new C.PolyPath64() : new C.Paths64();
  const openOut = new C.Paths64();
  const ok = tree
    ? c.ExecutePoly(CLIP_TYPES[op - 1], FILL_RULES[fill], closed, openOut)
    : c.ExecutePath(CLIP_TYPES[op - 1], FILL_RULES[fill], closed, openOut);
  const out = [];
  if (!ok) out.push(-1);
  else {
    if (tree) flattenTree(closed, out);
    else flattenRef(closed, out);
    flattenRef(openOut, out);
  }
  for (const x of [c, s, o, k, closed, openOut]) x.delete();
  return out;
}

function encode({ subjects, open, clips }) {
  const words = [];
  for (const paths of [subjects, open, clips]) {
    words.push(paths.length);
    for (const p of paths) {
      words.push(p.length);
      for (const [x, y] of p) words.push(x, y);
    }
  }
  return new Uint8Array(new Int32Array(words).buffer);
}

const hash = (words) => {
  let h = 0x811c9dc5 | 0;
  for (const v of words) h = Math.imul(h ^ v, 0x01000193);
  return h;
};

// Inputs: random polygons (self-intersecting ones too) at several scales,
// rectangles on a coarse grid (many horizontals and shared edges), and
// polylines cut by polygons.
function randomCases(n) {
  const r = rng(12345);
  const cases = [];
  const poly = (range, k) => Array.from({ length: k }, () => [Math.floor((r() - 0.5) * range), Math.floor((r() - 0.5) * range)]);
  const rect = (grid, cells) => {
    const x = Math.floor(r() * cells) * grid, y = Math.floor(r() * cells) * grid;
    const w = (1 + Math.floor(r() * cells / 2)) * grid, h = (1 + Math.floor(r() * cells / 2)) * grid;
    return r() < 0.5 ? [[x, y], [x + w, y], [x + w, y + h], [x, y + h]] : [[x, y], [x, y + h], [x + w, y + h], [x + w, y]];
  };
  const ranges = [100, 10000, 1e6, 2 ** 30];
  for (let i = 0; i < n; i++) {
    const kind = i % 3;
    if (kind === 0) {
      const range = ranges[i % ranges.length];
      cases.push({
        name: `random ${i} (range ${range})`,
        subjects: Array.from({ length: 1 + Math.floor(r() * 3) }, () => poly(range, 3 + Math.floor(r() * 10))),
        open: [],
        clips: Array.from({ length: 1 + Math.floor(r() * 3) }, () => poly(range, 3 + Math.floor(r() * 10))),
      });
    } else if (kind === 1) {
      cases.push({
        name: `grid ${i}`,
        subjects: Array.from({ length: 2 + Math.floor(r() * 6) }, () => rect(10, 10)),
        open: [],
        clips: Array.from({ length: 1 + Math.floor(r() * 5) }, () => rect(10, 10)),
      });
    } else {
      cases.push({
        name: `open ${i}`,
        subjects: [poly(1000, 3 + Math.floor(r() * 6))],
        open: Array.from({ length: 1 + Math.floor(r() * 3) }, () => poly(1000, 2 + Math.floor(r() * 6))),
        clips: Array.from({ length: 1 + Math.floor(r() * 2) }, () => poly(1000, 3 + Math.floor(r() * 8))),
      });
    }
  }
  return cases;
}

// Each GSI fixture tile's building rings against its water rings.
async function fixtureCases() {
  const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
  const cases = [];
  for (const x of (await readdir(dir)).sort()) {
    for (const f of (await readdir(path.join(dir, x))).sort()) {
      const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
      const rings = (name) => {
        const l = tile.layers[name];
        const out = [];
        for (let i = 0; l && i < l.length; i++) {
          const feature = l.feature(i);
          if (feature.type !== 3) continue;
          for (const ring of feature.loadGeometry()) out.push(ring.map((p) => [p.x, p.y]));
        }
        return out;
      };
      cases.push({ name: `gsi 14/${x}/${parseInt(f)}`, subjects: rings("building"), open: [], clips: rings("waterarea") });
    }
  }
  return cases;
}

const cases = [...randomCases(CASES), ...(await fixtureCases())];
let runs = 0, same = 0, sameGc = 0;
const failures = [];
for (const c of cases) {
  const input = encode(c);
  const addr = gc.copyIn(input);
  for (let op = 1; op <= 4; op++) {
    for (let fill = 0; fill <= 3; fill++) {
      for (const tree of [0, 1]) {
        runs++;
        const ref = reference(c, op, fill, tree);
        const got = mbt.clip_bytes(input, op, fill, tree);
        if (got === ref.join(",")) same++;
        else if (failures.length < 5) failures.push(`${c.name} op ${op} fill ${fill} tree ${tree}:\n  ref ${ref.slice(0, 40).join(",")}\n  got ${got.slice(0, 200)}`);
        if (gc.exports.clip_hash_mem(addr, input.length, op, fill, tree) === hash(ref)) sameGc++;
      }
    }
  }
}
console.log(`clipper golden: ${runs} runs over ${cases.length} cases; js identical ${same}, wasm-gc identical ${sameGc}`);
for (const f of failures) console.log(f);
if (same !== runs || sameGc !== runs) process.exitCode = 1;
