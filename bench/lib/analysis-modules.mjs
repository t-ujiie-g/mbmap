// The analysis worker's wasm-gc modules driven as analysis_worker/js/worker.mjs drives them (host Math, tables
// copied in and out per call), timing and results for the relate/shapes/surface/route/classify/viewshed benches.
import { readFile, readdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { hostNumber, hostText, writeInput } from "../../wasmio/js/host.mjs";
import { ROOT } from "./root.mjs";

const IMPORTS = { relate: () => ({}), shapes: () => ({ Math }), surface: () => ({ Math, host: hostText() }), viewshed: () => ({ Math }), route: () => ({ Math }) };
const wasmPath = (name) => path.join(ROOT, `_build/wasm-gc/release/build/${name}/${name}.wasm`);
const decoder = new TextDecoder();
const encoder = new TextEncoder();

export function outputOf(e, n) {
  if (n < 0) throw new Error(n === -2 ? "out of memory" : decoder.decode(outputOf(e, -n)));
  const at = e.output_addr();
  return new Uint8Array(e.memory.buffer.slice(at, at + n));
}
export const f64sOf = (e, n) => new Float64Array(outputOf(e, n * 8).buffer);

/** analysis.wasm plus the module `name`; `call` puts the datasets' tables (then `rest`) in its input. */
export async function loadModules(name) {
  let a;
  const { instance } = await WebAssembly.instantiate(await readFile(wasmPath("analysis_worker")), { Math, host: { number: hostNumber(() => a.memory) } });
  a = instance.exports;
  const m = name ? (await WebAssembly.instantiate(await readFile(wasmPath(`${name}_worker`)), IMPORTS[name]())).instance.exports : null;
  const counted = (n) => {
    if (n < 0) throw new Error(`analysis export failed (${n})`);
    return n;
  };
  const tableOf = (id) => outputOf(a, counted(a.table_out(id)));
  return {
    a,
    m,
    load(fc) {
      writeInput(a, [encoder.encode(JSON.stringify(fc))]);
      return counted(a.load());
    },
    dispose: (id) => a.dispose(id),
    tableOf,
    // The datasets' tables in the module's input; returns the first table's length.
    put(ids, rest = []) {
      const tables = ids.map(tableOf);
      writeInput(m, [...tables, ...rest]);
      return tables[0]?.length ?? 0;
    },
    // A table result kept as a new dataset, then dropped (the worker keeps it until `dispose`).
    store(n) {
      writeInput(a, [outputOf(m, n)]);
      a.dispose(counted(a.load_table()));
    },
  };
}

/** Median ms of one call of `f`: warmed up for `warmMs`, then `samples` samples of at least `sampleMs` each. */
export function time(f, { warmMs = 300, samples = 7, sampleMs = 50 } = {}) {
  const t = performance.now();
  for (let i = 0; i < 3 || performance.now() - t < warmMs; i++) f();
  const xs = [];
  for (let s = 0; s < samples; s++) {
    let n = 0;
    const t0 = performance.now();
    let dt;
    do {
      f();
      n++;
      dt = performance.now() - t0;
    } while (dt < sampleMs);
    xs.push(dt / n);
  }
  xs.sort((p, q) => p - q);
  return xs[xs.length >> 1];
}

/** Rows of { js, mbmap } ms (and other columns), with `mbmap / js`. */
export function rows() {
  const all = {};
  const row = (name, js, mbmap, extra = {}) => {
    all[name] = { js: round(js), mbmap: round(mbmap), ...Object.fromEntries(Object.entries(extra).map(([k, v]) => [k, round(v)])), ratio: round(mbmap / js) };
    const more = Object.keys(extra).map((k) => `, ${k} ${all[name][k]} ms`).join("");
    console.log(`${name}: js ${all[name].js} ms, mbmap ${all[name].mbmap} ms${more}, mbmap / js ${all[name].ratio}`);
  };
  return { all, row };
}
const round = (x) => (x >= 100 ? Math.round(x * 10) / 10 : Number(x.toPrecision(3)));

/** The first `count` GSI z14 fixture tiles; `layer(name)` gives a layer's features as GeoJSON. */
export async function gsiTiles(count) {
  const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
  const tiles = [];
  for (const x of (await readdir(dir)).sort()) {
    for (const f of (await readdir(path.join(dir, x))).sort()) {
      if (tiles.length >= count) return tiles;
      const tile = new VectorTile(new PbfReader(await readFile(path.join(dir, x, f))));
      tiles.push({
        key: `14/${x}/${parseInt(f)}`,
        layer(name) {
          const l = tile.layers[name];
          return Array.from({ length: l ? l.length : 0 }, (_, i) => ({ type: "Feature", properties: {}, geometry: l.feature(i).toGeoJSON(Number(x), parseInt(f), 14).geometry }));
        },
        properties: (name) => Array.from({ length: tile.layers[name]?.length ?? 0 }, (_, i) => tile.layers[name].feature(i).properties),
        names: () => Object.keys(tile.layers),
      });
    }
  }
  return tiles;
}

export const fc = (features) => ({ type: "FeatureCollection", features });

// Mulberry32: the same data on every run.
export function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Writes bench/results/<name>.json with the environment. */
export async function writeResults(name, params, rows) {
  const env = { runtime: `node ${process.version}`, v8: process.versions.v8, cpu: os.cpus()[0]?.model, platform: `${process.platform} ${process.arch}` };
  await writeFile(path.join(ROOT, `bench/results/${name}.json`), JSON.stringify({ env, params, rows }, null, 2) + "\n");
}

export const TIMING = "median ms of one call: warm-up 300 ms, then 7 samples of at least 50 ms each";
