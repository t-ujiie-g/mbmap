// Decode bench shared by the Node and Worker runners. Each decoder does the
// same work per tile: parse, then every feature's properties and geometry.
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { referenceTotals } from "./reference.mjs";

// Rows that do not decode geometry return null (no point count to check);
// a failed decode still returns -1. Mode bits as in entry/decode_all.mbt.
const MODE_PROPERTIES = 1, MODE_GEOMETRY = 2;

const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };

export function decoders({ mbtJs, gc }) {
  const list = [["js (@mapbox/vector-tile)", (buf) => referenceTotals(new VectorTile(new PbfReader(buf))).points]];
  if (mbtJs) list.push(["mbt-js", (buf) => mbtJs.decode_bytes(buf)]);
  if (gc) {
    list.push(["mbt-wasm-gc (copy + decode)", (buf) => gc.decode(buf).points]);
    list.push(["mbt-wasm-gc copy only", (buf) => { gc.exports.copy_mem(gc.copyIn(buf), buf.length); return null; }]);
    // Breakdown of the wasm-gc row; each includes the copy.
    for (const [label, mode] of [["parse only", 0], ["+ properties", MODE_PROPERTIES], ["+ geometry", MODE_GEOMETRY]]) {
      list.push([`mbt-wasm-gc ${label}`, (buf) => { const n = gc.exports.decode_mem_parts(gc.copyIn(buf), buf.length, mode); return n < 0 || mode & MODE_GEOMETRY ? n : null; }]);
    }
  }
  return list;
}

export function runDecodeBench(tiles, list, { warmup = 5, iterations = 15 } = {}) {
  const rows = [];
  for (const [name, fn] of list) {
    const perTile = [];
    let correct = true;
    for (const { key, buf, points } of tiles) {
      for (let i = 0; i < warmup; i++) fn(buf);
      const xs = [];
      for (let i = 0; i < iterations; i++) {
        const t0 = performance.now();
        const got = fn(buf);
        xs.push(performance.now() - t0);
        if (got !== null && got !== points) correct = false;
      }
      perTile.push({ key, ms: median(xs) });
    }
    const center = perTile.find((t) => t.key === "14/14552/6451")?.ms;
    rows.push({ name, correct, centerMs: center, medianTileMs: median(perTile.map((t) => t.ms)), totalMs: perTile.reduce((a, t) => a + t.ms, 0), perTile });
  }
  return { params: { tiles: tiles.length, warmup, iterations, statistic: "median per tile" }, rows };
}

export function printRows(result) {
  console.table(result.rows.map((r) => ({ name: r.name, ok: r.correct, center: r.centerMs.toFixed(2), medianTile: r.medianTileMs.toFixed(2), total: r.totalMs.toFixed(1) })));
}
