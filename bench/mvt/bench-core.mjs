// Rows of the mvt decode bench, shared by the Node and Worker runners. Each
// decoder does the same work per tile: parse, then every feature's properties
// and geometry; rows are checked against @mapbox/vector-tile's point count.
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { referenceTotals } from "./reference.mjs";

// decode_mem_parts mode bits, as in bench/entry/decode_all.mbt.
const MODE_PROPERTIES = 1, MODE_GEOMETRY = 2;

export function mvtRows({ mbtJs, gc }) {
  const points = (t) => (t.points ??= referenceTotals(new VectorTile(new PbfReader(t.buf))).points);
  const rows = [
    { name: "js (@mapbox/vector-tile)", run: (t) => referenceTotals(new VectorTile(new PbfReader(t.buf))).points, expect: points },
    { name: "mbt-js", run: (t) => mbtJs.decode_bytes(t.buf), expect: points },
    { name: "mbt-wasm-gc (copy + decode)", run: (t) => gc.exports.decode_mem(gc.copyIn(t.buf), t.buf.length), expect: points },
    { name: "mbt-wasm-gc copy only", run: (t) => gc.exports.copy_mem(gc.copyIn(t.buf), t.buf.length) },
  ];
  // Breakdown of the wasm-gc row; each includes the copy.
  for (const [label, mode] of [["parse only", 0], ["+ properties", MODE_PROPERTIES], ["+ geometry", MODE_GEOMETRY]]) {
    rows.push({
      name: `mbt-wasm-gc ${label}`,
      run: (t) => gc.exports.decode_mem_parts(gc.copyIn(t.buf), t.buf.length, mode),
      expect: mode & MODE_GEOMETRY ? points : undefined,
    });
  }
  return rows;
}
