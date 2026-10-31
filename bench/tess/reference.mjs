// JS reference for the fill pipeline, as MapLibre's fill bucket runs it:
// classifyRings(geometry, 500), then earcut per polygon.
import earcut, { deviation } from "earcut";
import { classifyRings } from "@maplibre/maplibre-gl-style-spec";

export const MAX_POLYGON_RINGS = 500;

// Same as bench/entry/tessellate.mbt's fnv.
const fnv = (h, v) => Math.imul(h ^ v, 0x01000193);
export const FNV_SEED = 0x811c9dc5 | 0;

// A classified polygon as earcut input, like MapLibre's subdivision `flatten`.
export function flattenPolygon(polygon) {
  const flat = [], holes = [];
  for (const ring of polygon) {
    if (ring.length === 0) continue;
    if (ring !== polygon[0]) holes.push(flat.length / 2);
    for (const p of ring) flat.push(p.x, p.y);
  }
  return { flat, holes };
}

export const classify = (geometry) => classifyRings(geometry, MAX_POLYGON_RINGS);

// Triangulates one polygon feature; returns its hash and per-polygon deviations.
export function fillFeature(geometry) {
  const vertices = [], indices = [], deviations = [];
  for (const polygon of classify(geometry)) {
    const { flat, holes } = flattenPolygon(polygon);
    const tris = earcut(flat, holes);
    deviations.push(deviation(flat, holes, 2, tris));
    const base = vertices.length / 2;
    vertices.push(...flat);
    for (const t of tris) indices.push(base + t);
  }
  let h = FNV_SEED;
  for (const v of vertices) h = fnv(h, v);
  for (const v of indices) h = fnv(h, v);
  return { hash: h, deviations, vertices: vertices.length / 2 };
}

export { fnv };
