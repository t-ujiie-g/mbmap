// Where mbmap/3d's models go: the transforms from a model's meters to Web Mercator and to the globe's
// unit sphere, and the points of GeoJSON data with their values.
export { multiply as mul } from "./gltf.ts";

/** A constant, or `["get", key]` for a feature's property. */
export type Value<T> = T | ["get", string];

/** Meters per radian of MapLibre's globe (`GLOBE_RADIUS`) and Web Mercator's sphere. */
export const EARTH_RADIUS = 6371008.8;
export const MERCATOR_RADIUS = 6378137;
const DEG = Math.PI / 180;

/** The light: Mapbox's default (azimuth 210°, polar 30°) in east, north, up. */
export const LIGHT = [Math.sin(30 * DEG) * Math.sin(210 * DEG), Math.sin(30 * DEG) * Math.cos(210 * DEG), Math.cos(30 * DEG)];

/** glTF's +Y up turned to +Z up: (x, y, z) to (x, -z, y), east, north, up. */
export const Y_UP = [1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1];

/** The transform of `scale`, `rotation` (degrees, z clockwise from above) and `translation` (meters). */
export function placement(scale: number[], rotation: number[], translation: number[]): Float64Array {
  const [rx, ry, rz] = [rotation[0] * DEG, rotation[1] * DEG, -rotation[2] * DEG];
  const [cx, sx, cy, sy, cz, sz] = [Math.cos(rx), Math.sin(rx), Math.cos(ry), Math.sin(ry), Math.cos(rz), Math.sin(rz)];
  // Rz * Ry * Rx, column-major.
  const r = [
    cz * cy, sz * cy, -sy,
    cz * sy * sx - sz * cx, sz * sy * sx + cz * cx, cy * sx,
    cz * sy * cx + sz * sx, sz * sy * cx - cz * sx, cy * cx,
  ];
  return new Float64Array([
    r[0] * scale[0], r[1] * scale[0], r[2] * scale[0], 0,
    r[3] * scale[1], r[4] * scale[1], r[5] * scale[1], 0,
    r[6] * scale[2], r[7] * scale[2], r[8] * scale[2], 0,
    translation[0], translation[1], translation[2], 1,
  ]);
}

/** From east, north, up meters at `lng`, `lat`, `height` to MapLibre's Mercator 0 to 1 (z in the same units). */
export function mercatorFrame(lng: number, lat: number, height: number): Float64Array {
  const x = (180 + lng) / 360;
  const y = (180 - (180 / Math.PI) * Math.log(Math.tan(Math.PI / 4 + (lat * DEG) / 2))) / 360;
  const k = 1 / (2 * Math.PI * MERCATOR_RADIUS * Math.cos(lat * DEG));
  return new Float64Array([k, 0, 0, 0, 0, -k, 0, 0, 0, 0, k, 0, x, y, height * k, 1]);
}

/** From east, north, up meters at `lng`, `lat`, `height` to MapLibre's unit sphere. */
export function sphereFrame(lng: number, lat: number, height: number): Float64Array {
  const [sl, cl, sp, cp] = [Math.sin(lng * DEG), Math.cos(lng * DEG), Math.sin(lat * DEG), Math.cos(lat * DEG)];
  const k = 1 / EARTH_RADIUS;
  const h = 1 + height / EARTH_RADIUS;
  return new Float64Array([cl * k, 0, -sl * k, 0, -sl * sp * k, cp * k, -cl * sp * k, 0, sl * cp * k, sp * k, cl * cp * k, 0, sl * cp * h, sp * h, cl * cp * h, 1]);
}

/** The 3x3 inverse transpose of `m`'s upper left (normals), column-major. */
export function normalMatrix(m: ArrayLike<number>): Float32Array {
  const [a, b, c, d, e, f, g, h, i] = [m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]];
  const det = a * (e * i - f * h) - d * (b * i - c * h) + g * (b * f - c * e) || 1;
  return new Float32Array([
    (e * i - f * h) / det, (g * f - d * i) / det, (d * h - g * e) / det,
    (h * c - b * i) / det, (a * i - g * c) / det, (g * b - a * h) / det,
    (b * f - e * c) / det, (d * c - a * f) / det, (a * e - d * b) / det,
  ]);
}

export function value<T>(v: Value<T> | undefined, props: Record<string, unknown>, fallback: T): T {
  if (Array.isArray(v) && v[0] === "get" && typeof v[1] === "string") {
    const got = props[v[1]];
    return (got === undefined || got === null ? fallback : got) as T;
  }
  return (v as T | undefined) ?? fallback;
}

/** `v` as three finite numbers, each a constant or `["get", key]` of `props`, else `fallback`. */
export function triple(v: unknown, props: Record<string, unknown>, fallback: number[]): number[] {
  const out = value(v as Value<unknown[]>, props, fallback);
  if (!Array.isArray(out) || out.length !== 3) return fallback;
  const numbers = out.map((e) => Number(value(e as Value<unknown>, props, NaN)));
  return numbers.every(Number.isFinite) ? numbers : fallback;
}

/** The points of `data` with their properties. */
export function points(data: unknown): { coords: number[]; props: Record<string, unknown> }[] {
  const out: { coords: number[]; props: Record<string, unknown> }[] = [];
  const visit = (g: any, props: Record<string, unknown>) => {
    if (!g || typeof g !== "object") return;
    if (g.type === "FeatureCollection") for (const f of Array.isArray(g.features) ? g.features : []) visit(f, {});
    else if (g.type === "Feature") visit(g.geometry, g.properties && typeof g.properties === "object" ? g.properties : {});
    else if (g.type === "Point" && Array.isArray(g.coordinates)) out.push({ coords: g.coordinates, props });
    else if (g.type === "MultiPoint" && Array.isArray(g.coordinates)) for (const c of g.coordinates) out.push({ coords: c, props });
  };
  visit(data, {});
  return out.filter((p) => Number.isFinite(p.coords[0]) && Number.isFinite(p.coords[1]));
}

