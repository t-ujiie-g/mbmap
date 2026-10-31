// The JS side of the analysis golden test and bench: Turf.js 7.4.0 and
// flatbush 4.6.2 over parsed GeoJSON, with the semantics mbmap documents.
import Flatbush from "flatbush";
import { area } from "@turf/area";
import { bbox } from "@turf/bbox";
import { booleanPointInPolygon } from "@turf/boolean-point-in-polygon";
import { centroid } from "@turf/centroid";
import { collect } from "@turf/collect";
import { length } from "@turf/length";

export const isPolygon = (f) => f.geometry && (f.geometry.type === "Polygon" || f.geometry.type === "MultiPolygon");

export const areas = (features) => Float64Array.from(features, (f) => area(f));
export const lengths = (features) => Float64Array.from(features, (f) => length(f, { units: "meters" }));
export const centroids = (features) => Float64Array.from(features.flatMap((f) => centroid(f).geometry.coordinates));
export const bboxes = (features) => Float64Array.from(features.flatMap((f) => bbox(f)));

export function index(boxes) {
  const n = boxes.length / 4;
  const ix = new Flatbush(n);
  for (let i = 0; i < n; i++) ix.add(boxes[i * 4], boxes[i * 4 + 1], boxes[i * 4 + 2], boxes[i * 4 + 3]);
  ix.finish();
  return ix;
}

// Point features with a point in some polygon feature (polygon kinds only),
// found through a flatbush index over the polygons, as an app would.
export function pointsWithin(points, polygons, polygonIndex) {
  const out = [];
  points.forEach((p, i) => {
    const coords = p.geometry?.type === "Point" ? [p.geometry.coordinates] : p.geometry?.type === "MultiPoint" ? p.geometry.coordinates : [];
    const inside = coords.some(([x, y]) =>
      polygonIndex.search(x, y, x, y).some((j) => isPolygon(polygons[j]) && booleanPointInPolygon([x, y], polygons[j])),
    );
    if (inside) out.push(i);
  });
  return out;
}

// Turf's `collect` per polygon, reduced to count, numeric count and the sum
// of `property` added in point order (three numbers per polygon).
export function collected(polygons, points, property) {
  const tagged = {
    type: "FeatureCollection",
    features: points.map((p, i) => ({ ...p, properties: { __i: i } })).filter((p) => p.geometry?.type === "Point"),
  };
  const polys = { type: "FeatureCollection", features: polygons.map((f) => ({ ...f, properties: {} })) };
  collect(polys, tagged, "__i", "__hits");
  const out = new Float64Array(polygons.length * 3);
  polys.features.forEach((f, i) => {
    if (!isPolygon(f)) return;
    const hits = f.properties.__hits.sort((a, b) => a - b);
    let numbers = 0;
    let sum = 0;
    for (const h of hits) {
      const v = points[h].properties?.[property];
      if (typeof v === "number") {
        numbers++;
        sum += v;
      }
    }
    out.set([hits.length, numbers, sum], i * 3);
  });
  return out;
}

// Point counts per grid cell, the rule of `@analysis.grid_count`.
export function grid(points, [x0, y0, x1, y1], cols, rows) {
  const out = new Int32Array(cols * rows);
  const w = (x1 - x0) / cols;
  const h = (y1 - y0) / rows;
  for (const p of points) {
    const g = p.geometry;
    const coords = g?.type === "Point" ? [g.coordinates] : g?.type === "MultiPoint" ? g.coordinates : [];
    for (const [x, y] of coords) {
      if (x >= x0 && x <= x1 && y >= y0 && y <= y1) {
        out[Math.min(Math.trunc((y - y0) / h), rows - 1) * cols + Math.min(Math.trunc((x - x0) / w), cols - 1)]++;
      }
    }
  }
  return out;
}

// Seeded query boxes and points over `extent`.
export function queries(extent, count, seed = 7) {
  let s = seed;
  const rand = () => (s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296;
  const [x0, y0, x1, y1] = extent;
  const boxes = [];
  const points = [];
  for (let i = 0; i < count; i++) {
    const x = x0 + rand() * (x1 - x0);
    const y = y0 + rand() * (y1 - y0);
    const w = rand() * (x1 - x0) * 0.05;
    const h = rand() * (y1 - y0) * 0.05;
    boxes.push([x, y, x + w, y + h]);
    points.push([x0 + rand() * (x1 - x0), y0 + rand() * (y1 - y0)]);
  }
  return { boxes, points };
}

export function extentOf(boxes) {
  const e = [Infinity, Infinity, -Infinity, -Infinity];
  for (let i = 0; i < boxes.length; i += 4) {
    e[0] = Math.min(e[0], boxes[i]);
    e[1] = Math.min(e[1], boxes[i + 1]);
    e[2] = Math.max(e[2], boxes[i + 2]);
    e[3] = Math.max(e[3], boxes[i + 3]);
  }
  return e;
}
