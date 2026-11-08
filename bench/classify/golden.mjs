// mbmap/analysis's classification (npm/src/classify.ts) vs simple-statistics 8.0.0 (jenks, ckmeans,
// quantile, equal intervals, statistics) and geostats 2.1.0 (standard deviation classes) on random
// numbers and GSI attributes; every number must be identical (Object.is).
// Usage: node --experimental-strip-types classify/golden.mjs; writes bench/results/classify-golden.json.
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import * as ss from "simple-statistics";
import geostats from "geostats";
import { classBreaks, statistics } from "../../npm/src/classify.ts";
import { ROOT } from "../lib/root.mjs";

const results = {};
const failures = [];
const same = (x, y) => (Array.isArray(x) ? Array.isArray(y) && x.length === y.length && x.every((v, i) => same(v, y[i])) : Object.is(x, y));
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, identical: 0 });
  r.cases++;
  if (same(want, got)) r.identical++;
  else if (failures.length < 30) failures.push({ group, label, want: JSON.stringify(want)?.slice(0, 300), got: JSON.stringify(got)?.slice(0, 300) });
}
const attempt = (f) => {
  try {
    return f();
  } catch (err) {
    return `error: ${err.message}`;
  }
};

// What simple-statistics gives, null where it throws.
const orNull = (f) => {
  try {
    return f();
  } catch {
    return null;
  }
};

// Breaks with an undefined bound (fewer distinct values than classes) as null.
const complete = (b) => (b && b.every((v) => v !== undefined) ? b : null);

// geostats' standard deviation classes, its statistics replaced by simple-statistics' exact ones.
function geostatsStdDev(x, n, matchBounds) {
  const g = new geostats(x);
  g.stat_mean = ss.mean(x);
  g.stat_stddev = ss.standardDeviation(x);
  return matchBounds ? g.getClassStdDeviation(n, true) : g.getClassStdDeviation(n);
}

function compare(group, x) {
  const st = statistics(x);
  check(`${group} statistics`, x.length, [x.length, ss.min(x), ss.max(x), ss.sum(x), ss.mean(x), ss.median(x), ss.variance(x), ss.standardDeviation(x)],
    st && [st.count, st.min, st.max, st.sum, st.mean, st.median, st.variance, st.standardDeviation]);
  for (const n of [1, 2, 3, 5, 7, 10]) {
    if (x.length <= 3000) check(`${group} jenks`, `${x.length}, ${n}`, complete(orNull(() => ss.jenks(x, n))), attempt(() => classBreaks(x, n, "jenks")));
    check(`${group} ckmeans`, `${x.length}, ${n}`, n > x.length ? null : ss.ckmeans(x, n).map((c) => c[0]).concat([ss.max(x)]).slice(0, Math.min(n, new Set(x).size === 1 ? 1 : n) + 1), attempt(() => classBreaks(x, n, "ckmeans")));
    check(`${group} quantile`, `${x.length}, ${n}`, ss.quantile(x, Array.from({ length: n + 1 }, (_, i) => i / n)), attempt(() => classBreaks(x, n, "quantile")));
    check(`${group} equalInterval`, `${x.length}, ${n}`, ss.equalIntervalBreaks(x, n), attempt(() => classBreaks(x, n, "equalInterval")));
    for (const matchBounds of [false, true]) {
      check(`${group} standardDeviation`, `${x.length}, ${n}, ${matchBounds}`, geostatsStdDev(x, n, matchBounds), attempt(() => classBreaks(x, n, "standardDeviation", { matchBounds })));
    }
  }
}

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(193);
for (let k = 0; k < 40; k++) compare("random", Array.from({ length: 10 + Math.floor(rand() * 1500) }, () => (rand() - 0.3) * 10 ** (rand() * 6)));
for (let k = 0; k < 40; k++) compare("ties", Array.from({ length: 10 + Math.floor(rand() * 500) }, () => Math.floor(rand() * 12)));
compare("one value", [5, 5, 5, 5]);
compare("two values", [1, 9]);
for (let k = 0; k < 20; k++) compare("signed zeros", Array.from({ length: 10 + Math.floor(rand() * 1500) }, () => [0, -0, 1, -1, 2.5][Math.floor(rand() * 5)]));

// Numeric properties of GSI features, per tile and key.
const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
let tiles = 0;
for (const x of (await readdir(dir)).sort()) {
  for (const f of (await readdir(path.join(dir, x))).sort()) {
    if (tiles++ >= 6) break;
    const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
    for (const [name, layer] of Object.entries(tile.layers)) {
      const byKey = {};
      for (let i = 0; i < layer.length; i++) {
        for (const [key, v] of Object.entries(layer.feature(i).properties)) if (typeof v === "number") (byKey[key] ??= []).push(v);
      }
      for (const [key, values] of Object.entries(byKey)) if (values.length >= 10) compare(`gsi ${name}.${key}`.replace(/\..*/, ""), values);
    }
  }
}

const merged = {};
for (const [g, r] of Object.entries(results)) {
  const key = g.replace(/^gsi \S+/, "gsi");
  const m = (merged[key] ??= { cases: 0, identical: 0 });
  m.cases += r.cases;
  m.identical += r.identical;
}
console.table(merged);
for (const f of failures.slice(0, 10)) console.log(JSON.stringify(f));
const ok = failures.length === 0;
await writeFile(path.join(ROOT, "bench/results/classify-golden.json"), JSON.stringify({ results: merged, failures, ok }, null, 2) + "\n");
console.log(ok ? "all identical" : `${failures.length} differ`);
process.exit(ok ? 0 : 1);
