// tess's subdivision (bench/entry/subdivision.mbt) vs MapLibre 6.16.0's subdividePolygon and
// subdivideVertexLine, exactly: vertices, triangles and outline lines. Inputs: the GSI fixtures'
// polygons (classifyRings as the fill bucket) and lines, and seeded random polygons and lines.
import { readFile } from "node:fs/promises";
import path from "node:path";
import Point from "@mapbox/point-geometry";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { subdividePolygon, subdivideVertexLine } from "maplibre-src/render/subdivision.ts";
import { SubdivisionGranularityExpression } from "maplibre-src/render/subdivision_granularity_settings.ts";
import { classify } from "./reference.mjs";
import { nodeImportJs } from "../lib/node-io.mjs";
import { ENTRY_JS } from "../lib/entry.mjs";
import { ROOT } from "../lib/root.mjs";

const mbt = await nodeImportJs(ENTRY_JS);
const join = (a) => a.join(",");
let logged = 0;
console.error = () => { logged++; };

function reference(polygon, canonical, granularity, outline) {
  let r;
  try {
    r = subdividePolygon(polygon, canonical, granularity, outline);
  } catch {
    return "fail";
  }
  return `${join(r.verticesFlattened)}|${join(r.indicesTriangles ?? [])}|${r.indicesLineList.map(join).join(";")}`;
}

function ours(polygon, canonical, granularity, outline) {
  const coords = [], ends = [];
  for (const ring of polygon) {
    for (const p of ring) coords.push(p.x, p.y);
    ends.push(coords.length / 2);
  }
  const c = canonical ?? { z: -1, x: 0, y: 0 };
  return mbt.subdivide_polygon(coords, ends, granularity, c.z, c.x, c.y, outline);
}

const stats = {};
function count(group, same, detail) {
  const s = (stats[group] ??= { identical: 0, differ: 0, failed: 0 });
  if (same) s.identical++;
  else {
    s.differ++;
    if (s.differ <= 3) console.log(`DIFF ${group}: ${detail}`);
  }
}

function comparePolygon(group, polygon, canonical, granularity, outline = true) {
  const want = reference(polygon, canonical, granularity, outline);
  const got = ours(polygon, canonical, granularity, outline);
  count(group, want === got, `granularity ${granularity}, tile ${JSON.stringify(canonical)}\n  want ${want.slice(0, 300)}\n  got  ${got.slice(0, 300)}`);
  if (want === "fail") stats[group].failed++;
}

function compareLine(group, points, granularity, isRing) {
  const want = join(subdivideVertexLine(points, granularity, isRing).flatMap((p) => [p.x, p.y]));
  const got = mbt.subdivide_vertex_line(points.flatMap((p) => [p.x, p.y]), granularity, isRing);
  count(group, want === got, `granularity ${granularity}, ring ${isRing}\n  want ${want.slice(0, 300)}\n  got  ${got.slice(0, 300)}`);
}

// Seeded mulberry32.
function random(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = random(20261108);
const int = (lo, hi) => lo + Math.floor(rand() * (hi - lo + 1));
const SPECIAL_Y = [0, 8192, -32768, 32767, 4096];
function coord(lo, hi, grid) {
  const r = rand();
  if (r < 0.15) return Math.round(int(lo, hi) / grid) * grid;
  if (r < 0.2) return SPECIAL_Y[int(0, SPECIAL_Y.length - 1)];
  return int(lo, hi);
}
function randomRing(cx, cy, radius, n, grid) {
  const ring = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * 2 * Math.PI + rand() * 0.3;
    const r = radius * (0.4 + rand() * 0.6);
    let x = Math.round(cx + Math.cos(a) * r), y = Math.round(cy + Math.sin(a) * r);
    if (rand() < 0.1) x = Math.round(x / grid) * grid;
    if (rand() < 0.1) y = Math.round(y / grid) * grid;
    if (rand() < 0.03) y = SPECIAL_Y[int(0, 3)];
    ring.push(new Point(x, y));
  }
  if (rand() < 0.5) ring.push(ring[0].clone());
  return ring;
}

const GRANULARITIES = [1, 2, 4, 32, 128];
const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
for (const key of Object.keys(manifest.tiles)) {
  const [z, x, y] = key.split("/").map(Number);
  const tiles = [{ z, x, y }, { z, x, y: 0 }, { z, x, y: (1 << z) - 1 }, { z: 0, x: 0, y: 0 }];
  const buf = new Uint8Array(await readFile(path.join(ROOT, `bench/fixtures/gsi-bvmap/${key}.pbf`)));
  const tile = new VectorTile(new PbfReader(buf));
  for (const layer of Object.values(tile.layers)) {
    for (let i = 0; i < layer.length; i++) {
      const f = layer.feature(i);
      const geometry = f.loadGeometry();
      if (f.type === 3) {
        for (const polygon of classify(geometry)) {
          for (const g of GRANULARITIES) {
            for (const t of tiles) comparePolygon("gsi polygons", polygon, t, g);
          }
          comparePolygon("gsi polygons", polygon, tiles[0], 4, false);
        }
      } else if (f.type === 2) {
        for (const line of geometry) {
          for (const g of [0, 1, 2, 3, 4, 8, 16, 32, 64, 100, 128, 256, 512]) compareLine("gsi lines", line, g, false);
        }
      }
    }
  }
}

for (let n = 0; n < 3000; n++) {
  const outer = randomRing(int(-500, 8700), int(-500, 8700), int(50, 6000), int(3, 40), 1 << int(5, 12));
  const polygon = [outer];
  for (let h = int(0, 3); h > 0; h--) polygon.push(randomRing(int(0, 8192), int(0, 8192), int(20, 1500), int(3, 12), 512));
  if (rand() < 0.05) polygon.push([]);
  const g = [1, 2, 3, 4, 8, 32, 128, 512][int(0, 7)];
  const t = [undefined, { z: 3, x: 2, y: 0 }, { z: 3, x: 2, y: 7 }, { z: 0, x: 0, y: 0 }, { z: 5, x: 3, y: 9 }][int(0, 4)];
  comparePolygon("random polygons", polygon, t, g, rand() < 0.9);
}
// Vertices out of Int16 make MapLibre throw.
comparePolygon("random polygons", [[new Point(0, 0), new Point(40000, 0), new Point(0, 100)]], undefined, 4);
for (let n = 0; n < 5000; n++) {
  const points = [];
  for (let k = int(1, 12); k > 0; k--) points.push(new Point(coord(-9000, 17000, 256), coord(-9000, 17000, 256)));
  if (rand() < 0.2 && points.length > 1) points.push(points[0].clone());
  compareLine("random lines", points, int(0, 512), rand() < 0.4);
}

for (const [base, min] of [[128, 2], [512, 0], [128, 32], [0, 0], [3, 1]]) {
  const expr = new SubdivisionGranularityExpression(base, min);
  const fill = new SubdivisionGranularityExpression(128, 2);
  const line = new SubdivisionGranularityExpression(512, 0);
  for (let z = -2; z <= 40; z++) {
    const want = [expr, fill, line].map((e) => e.getGranularityForZoomLevel(z)).join(",");
    count("granularity", mbt.subdivision_granularity(base, min, z) === want, `${base}, ${min} at ${z}`);
  }
}

let differ = 0;
for (const [group, s] of Object.entries(stats)) {
  differ += s.differ;
  console.log(`${group}: ${s.identical} identical, ${s.differ} differ${s.failed ? ` (${s.failed} where MapLibre throws)` : ""}`);
}
if (logged) console.log(`MapLibre logged ${logged} subdivision errors`);
process.exitCode = differ ? 1 : 0;
