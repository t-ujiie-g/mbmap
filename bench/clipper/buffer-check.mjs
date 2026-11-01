// Checks that geodesic buffers lie at their distance on the ground: every
// vertex of each buffer's outer boundary is measured, with GeographicLib's
// geodesics on WGS84, to the input geometry (its edges sampled densely). Points,
// lines and polygons at several latitudes and distances go through the
// analysis and geometry wasm modules as the analysis worker uses them.
// Usage: node clipper/buffer-check.mjs; writes bench/results/buffer-geodesic.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import geodesic from "geographiclib-geodesic";
import { hostNumber } from "../../wasmio/js/host.mjs";
import { ROOT } from "../lib/root.mjs";

const WGS84 = geodesic.Geodesic.WGS84;
let a;
const { instance: ai } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm")),
  { Math: { sin: Math.sin, cos: Math.cos, atan2: Math.atan2 }, host: { number: hostNumber(() => a.memory) } },
);
a = ai.exports;
const { instance: gi } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/geometry_worker/geometry_worker.wasm")), {});
const g = gi.exports;
const put = (e, bytes) => {
  const at = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
};
const out = (e, n) => {
  if (n < 0) throw new Error(new TextDecoder().decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
};
const { tableToGeoJSON } = await import("../../analysis_worker/js/table.mjs");

function buffer(feature, meters) {
  put(a, new TextEncoder().encode(JSON.stringify(feature)));
  const id = a.load();
  put(g, out(a, a.table_out(id)));
  return tableToGeoJSON(out(g, g.buffer(meters, 0, 0, 0, 0))).features[0].geometry;
}

// Input vertices and edges sampled every 1/400 of their length.
function samples(geometry) {
  const lines = geometry.type === "Point" ? [[geometry.coordinates]] : geometry.type === "LineString" ? [geometry.coordinates] : geometry.coordinates;
  const pts = [];
  for (const line of lines) {
    if (line.length === 1) pts.push(line[0]);
    for (let i = 1; i < line.length; i++) {
      const [x0, y0] = line[i - 1], [x1, y1] = line[i];
      for (let k = 0; k <= 400; k++) pts.push([x0 + ((x1 - x0) * k) / 400, y0 + ((y1 - y0) * k) / 400]);
    }
  }
  return pts;
}
const distanceTo = (pts, [lon, lat]) => Math.min(...pts.map(([x, y]) => WGS84.Inverse(lat, lon, y, x, geodesic.Geodesic.DISTANCE).s12));

const results = [];
for (const lat of [0, 35.68, 60, 80]) {
  for (const meters of [10, 1000, 50000]) {
    const span = (meters * 2) / 111000;
    const shapes = {
      point: { type: "Point", coordinates: [139.77, lat] },
      line: { type: "LineString", coordinates: [[139.77, lat], [139.77 + span, lat + span / 2], [139.77 + span * 2, lat]] },
      polygon: { type: "Polygon", coordinates: [[[139.77, lat], [139.77 + span, lat], [139.77 + span, lat + span], [139.77, lat + span], [139.77, lat]]] },
    };
    for (const [kind, geometry] of Object.entries(shapes)) {
      const result = buffer({ type: "Feature", properties: {}, geometry }, meters);
      const outer = result.type === "Polygon" ? result.coordinates[0] : result.coordinates[0][0];
      const pts = samples(geometry);
      let worst = 0;
      for (const v of outer) worst = Math.max(worst, Math.abs(distanceTo(pts, v) - meters));
      results.push({ lat, meters, kind, vertices: outer.length, maxErrorMeters: worst, maxRelativeError: worst / meters });
    }
  }
}
for (const r of results) console.log(`${r.kind.padEnd(7)} lat ${String(r.lat).padStart(5)} ${String(r.meters).padStart(6)} m: ${r.vertices} vertices, max error ${r.maxErrorMeters.toFixed(4)} m (${(r.maxRelativeError * 100).toFixed(4)}%)`);
await writeFile(path.join(ROOT, "bench/results/buffer-geodesic.json"), JSON.stringify({ reference: "GeographicLib 2.2.0 (WGS84 geodesics)", results }, null, 2) + "\n");
