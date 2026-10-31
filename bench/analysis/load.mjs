// The shipped analysis wasm (analysis_worker) driven directly, without its
// worker glue, for the golden test and the bench.
import { numberAt } from "../lib/entry.mjs";

export const ANALYSIS_WASM = "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm";
export const MEASURE = { area: 0, length: 1, centroid: 2, bbox: 3 };

export async function loadAnalysis(fetchBytes) {
  let e = null;
  const host = { number: (addr, len) => numberAt(() => e.memory.buffer, addr, len) };
  const { instance } = await WebAssembly.instantiate(await fetchBytes(ANALYSIS_WASM), {
    Math: { sin: Math.sin, cos: Math.cos, atan2: Math.atan2 },
    host,
  });
  e = instance.exports;
  const input = (bytes) => {
    const at = e.prepare_input(bytes.length);
    if (at < 0) throw new Error("input too large");
    new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
  };
  const counted = (n) => {
    if (n < 0) throw new Error(`analysis export failed (${n})`);
    return n;
  };
  const f64s = (n) => new Float64Array(e.memory.buffer, e.output_addr(), counted(n)).slice();
  const i32s = (n) => new Int32Array(e.memory.buffer, e.output_addr(), counted(n)).slice();
  const encoder = new TextEncoder();
  return {
    exports: e,
    load(bytes) {
      input(bytes);
      return counted(e.load());
    },
    dispose: (id) => e.dispose(id),
    measure: (id, kind) => f64s(e.measure(id, kind)),
    search: (id, b) => i32s(e.search(id, b[0], b[1], b[2], b[3])),
    nearest: (id, x, y, k) => i32s(e.nearest(id, x, y, k, Infinity)),
    within: (points, polygons) => i32s(e.within(points, polygons)),
    collect(polygons, points, property) {
      input(encoder.encode(property));
      return f64s(e.collect(polygons, points));
    },
    grid: (id, b, cols, rows) => i32s(e.grid(id, b[0], b[1], b[2], b[3], cols, rows)),
  };
}
