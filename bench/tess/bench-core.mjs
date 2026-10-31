// Rows of the tess bench, shared by the Node and Worker runners. Fill rows
// cover the bench style's fill layers; the JS rows run MapLibre's fill
// pipeline (classifyRings + earcut) and give the vertex count mbmap must match.
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import earcut from "earcut";
import { classify, flattenPolygon } from "./reference.mjs";
import { createParser } from "../maplibre/parse-core.ts";
import style from "../maplibre/style.json";

const FILL_LAYERS = ["waterarea", "structurea", "building"];

// tessellate_tile mode bits, as in bench/entry/tessellate.mbt.
const MODE_FILL = 1, MODE_LINE = 2;

function* fillGeometries(buf) {
  const tile = new VectorTile(new PbfReader(buf));
  for (const name of FILL_LAYERS) {
    const layer = tile.layers[name];
    if (!layer) continue;
    for (let i = 0; i < layer.length; i++) {
      const f = layer.feature(i);
      if (f.type === 3) yield f.loadGeometry();
    }
  }
}

function jsDecode(buf) {
  let points = 0;
  for (const g of fillGeometries(buf)) for (const ring of g) points += ring.length;
  return points;
}

function jsFill(buf) {
  let vertices = 0;
  for (const g of fillGeometries(buf)) {
    for (const polygon of classify(g)) {
      const { flat, holes } = flattenPolygon(polygon);
      earcut(flat, holes);
      vertices += flat.length / 2;
    }
  }
  return vertices;
}

export function tessRows({ mbtJs, gc }) {
  const fillVertices = (t) => (t.fillVertices ??= jsFill(t.buf));
  const mem = (mode) => (t) => gc.exports.tess_mem(gc.copyIn(t.buf), t.buf.length, mode);
  const maplibreParse = createParser(style);
  return [
    { name: "maplibre WorkerTile.parse (same style)", run: (t) => maplibreParse(t.key, t.buf) },
    { name: "js decode only (fill layers)", run: (t) => jsDecode(t.buf) },
    { name: "js decode + classifyRings + earcut", run: (t) => jsFill(t.buf), expect: fillVertices },
    { name: "mbt-wasm-gc decode only (all drawn layers)", run: mem(0) },
    { name: "mbt-wasm-gc decode + fills", run: mem(MODE_FILL), expect: fillVertices },
    { name: "mbt-wasm-gc decode + lines", run: mem(MODE_LINE) },
    { name: "mbt-wasm-gc decode + fills + lines", run: mem(MODE_FILL | MODE_LINE) },
    { name: "mbt-js decode + fills + lines", run: (t) => mbtJs.tess_bytes(t.buf, MODE_FILL | MODE_LINE) },
  ];
}
