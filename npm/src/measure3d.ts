// Measuring between 3D points on WGS 84 for mbmap/3d. Import-free, so that `npm test` can load it.

/** `[longitude, latitude, height]`: degrees and meters above the ellipsoid. */
export type Position3d = [number, number, number];

/**
 * What `measure3d` gives: `length` the straight-line (slant) distance along the points, `horizontal` and
 * `vertical` its parts across and up, each edge in the east, north, up frame at its first point (`vertical`
 * signed, last height minus first); `distances` the slant distance to each point; for a closed ring `area`
 * its surface (a facade as it is) and `horizontalArea` its footprint, in the frame at its centroid.
 */
export interface Measure3d {
  length: number;
  horizontal: number;
  vertical: number;
  area: number;
  horizontalArea: number;
  distances: number[];
}

const A = 6378137;
const E2 = (1 / 298.257223563) * (2 - 1 / 298.257223563);
const DEG = Math.PI / 180;

/** `p` in Earth-centered, Earth-fixed meters. */
export function ecef(p: Position3d): [number, number, number] {
  const [sl, cl, sp, cp] = [Math.sin(p[0] * DEG), Math.cos(p[0] * DEG), Math.sin(p[1] * DEG), Math.cos(p[1] * DEG)];
  const n = A / Math.sqrt(1 - E2 * sp * sp);
  return [(n + p[2]) * cp * cl, (n + p[2]) * cp * sl, (n * (1 - E2) + p[2]) * sp];
}

/** `d` (ECEF meters) in the east, north, up frame at longitude `lng`, latitude `lat`. */
function enu(d: number[], lng: number, lat: number): [number, number, number] {
  const [sl, cl, sp, cp] = [Math.sin(lng * DEG), Math.cos(lng * DEG), Math.sin(lat * DEG), Math.cos(lat * DEG)];
  return [-sl * d[0] + cl * d[1], -sp * cl * d[0] - sp * sl * d[1] + cp * d[2], cp * cl * d[0] + cp * sl * d[1] + sp * d[2]];
}

/** Distances and, `closed`, the area of the ring through `points`. */
export function measure3d(points: Position3d[], options: { closed?: boolean } = {}): Measure3d {
  const xyz = points.map(ecef);
  const ring = options.closed && points.length > 2;
  const edges = ring ? points.length : points.length - 1;
  const distances = [0];
  let length = 0;
  let horizontal = 0;
  for (let i = 0; i < edges; i++) {
    const j = (i + 1) % points.length;
    const d = xyz[j].map((v, k) => v - xyz[i][k]);
    const [e, n] = enu(d, points[i][0], points[i][1]);
    length += Math.hypot(d[0], d[1], d[2]);
    horizontal += Math.hypot(e, n);
    if (i < points.length - 1) distances.push(length);
  }
  let area = 0;
  let horizontalArea = 0;
  if (ring) {
    const lng = points.reduce((s, p) => s + p[0], 0) / points.length;
    const lat = points.reduce((s, p) => s + p[1], 0) / points.length;
    const c = [0, 1, 2].map((k) => xyz.reduce((s, v) => s + v[k], 0) / xyz.length);
    const local = xyz.map((v) => enu([v[0] - c[0], v[1] - c[1], v[2] - c[2]], lng, lat));
    // Newell's normal: twice the area of the ring's plane, its up part twice the footprint.
    const normal = [0, 0, 0];
    local.forEach((a, i) => {
      const b = local[(i + 1) % local.length];
      normal[0] += (a[1] - b[1]) * (a[2] + b[2]);
      normal[1] += (a[2] - b[2]) * (a[0] + b[0]);
      normal[2] += (a[0] - b[0]) * (a[1] + b[1]);
    });
    area = Math.hypot(normal[0], normal[1], normal[2]) / 2;
    horizontalArea = Math.abs(normal[2]) / 2;
  }
  const vertical = points.length ? points[points.length - 1][2] - points[0][2] : 0;
  return { length, horizontal, vertical, area, horizontalArea, distances };
}
