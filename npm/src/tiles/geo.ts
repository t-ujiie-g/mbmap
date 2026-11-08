// The geometry 3D Tiles are selected with, as @loaders.gl/tiles 4.5.4 does it through math.gl 4.1
// (MIT): the WGS 84 ellipsoid (cartographic and Cartesian positions, east-north-up frames), oriented
// boxes and spheres in ECEF meters, planes and the culling volume's plane masks. Import-free.

export type Vec3 = [number, number, number];

/** WGS 84's radii and the derived constants math.gl keeps. */
const RX = 6378137.0;
const RZ = 6356752.3142451793;
const RADII_SQUARED: Vec3 = [RX * RX, RX * RX, RZ * RZ];
const ONE_OVER_RADII: Vec3 = [1 / RX, 1 / RX, 1 / RZ];
const ONE_OVER_RADII_SQUARED: Vec3 = [1 / (RX * RX), 1 / (RX * RX), 1 / (RZ * RZ)];
const CENTER_TOLERANCE_SQUARED = 0.1;
const EPSILON12 = 1e-12;
const DEGREES = 180 / Math.PI;
const RADIANS = Math.PI / 180;

export const dot = (a: ArrayLike<number>, b: ArrayLike<number>) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
export const sub = (a: ArrayLike<number>, b: ArrayLike<number>): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
export const add = (a: ArrayLike<number>, b: ArrayLike<number>): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const scale = (a: ArrayLike<number>, k: number): Vec3 => [a[0] * k, a[1] * k, a[2] * k];
export const length = (a: ArrayLike<number>) => Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
export const cross = (a: ArrayLike<number>, b: ArrayLike<number>): Vec3 => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

/** `a` scaled to length 1 (math.gl's `normalize`: unchanged when 0). */
export function normalize(a: ArrayLike<number>): Vec3 {
  const len = length(a);
  return len > 0 ? [a[0] / len, a[1] / len, a[2] / len] : [a[0], a[1], a[2]];
}

/** ECEF meters of longitude and latitude in degrees and a height in meters above the ellipsoid. */
export function toCartesian(lngDeg: number, latDeg: number, height: number): Vec3 {
  const lng = lngDeg * RADIANS;
  const lat = latDeg * RADIANS;
  const cosLat = Math.cos(lat);
  const n = normalize([cosLat * Math.cos(lng), cosLat * Math.sin(lng), Math.sin(lat)]);
  const k: Vec3 = [RADII_SQUARED[0] * n[0], RADII_SQUARED[1] * n[1], RADII_SQUARED[2] * n[2]];
  const gamma = Math.sqrt(dot(n, k));
  return [k[0] / gamma + n[0] * height, k[1] / gamma + n[1] * height, k[2] / gamma + n[2] * height];
}

/** `p` moved along the ellipsoid's normal onto its surface (math.gl's `scaleToGeodeticSurface`). */
function scaleToGeodeticSurface(p: ArrayLike<number>): Vec3 | undefined {
  const [x, y, z] = [p[0], p[1], p[2]];
  const x2 = x * x * ONE_OVER_RADII[0] * ONE_OVER_RADII[0];
  const y2 = y * y * ONE_OVER_RADII[1] * ONE_OVER_RADII[1];
  const z2 = z * z * ONE_OVER_RADII[2] * ONE_OVER_RADII[2];
  const squaredNorm = x2 + y2 + z2;
  const ratio = Math.sqrt(1.0 / squaredNorm);
  if (!Number.isFinite(ratio)) return undefined;
  const intersection = scale(p, ratio);
  if (squaredNorm < CENTER_TOLERANCE_SQUARED) return intersection;
  const [ox, oy, oz] = ONE_OVER_RADII_SQUARED;
  const gradient: Vec3 = [intersection[0] * ox * 2.0, intersection[1] * oy * 2.0, intersection[2] * oz * 2.0];
  let lambda = ((1.0 - ratio) * length(p)) / (0.5 * length(gradient));
  let correction = 0.0;
  let xm: number;
  let ym: number;
  let zm: number;
  let func: number;
  let steps = 0;
  do {
    lambda -= correction;
    xm = 1.0 / (1.0 + lambda * ox);
    ym = 1.0 / (1.0 + lambda * oy);
    zm = 1.0 / (1.0 + lambda * oz);
    const xm2 = xm * xm;
    const ym2 = ym * ym;
    const zm2 = zm * zm;
    func = x2 * xm2 + y2 * ym2 + z2 * zm2 - 1.0;
    const denominator = x2 * xm2 * xm * ox + y2 * ym2 * ym * oy + z2 * zm2 * zm * oz;
    correction = func / (-2.0 * denominator);
  } while (Math.abs(func) > EPSILON12 && ++steps < 100);
  return [x * xm, y * ym, z * zm];
}

/** Longitude and latitude in degrees and the height above the ellipsoid of ECEF point `p`. */
export function toCartographic(p: ArrayLike<number>): Vec3 | undefined {
  const point = scaleToGeodeticSurface(p);
  if (!point) return undefined;
  const n = normalize([point[0] * ONE_OVER_RADII_SQUARED[0], point[1] * ONE_OVER_RADII_SQUARED[1], point[2] * ONE_OVER_RADII_SQUARED[2]]);
  const h = sub(p, point);
  const height = Math.sign(dot(h, p)) * length(h);
  return [Math.atan2(n[1], n[0]) * DEGREES, Math.asin(n[2]) * DEGREES, height];
}

/** The east-north-up frame at ECEF `origin` to ECEF, column-major (math.gl's `eastNorthUpToFixedFrame`). */
export function eastNorthUp(origin: ArrayLike<number>): Float64Array {
  let east: Vec3;
  let north: Vec3;
  let up: Vec3;
  if (Math.abs(origin[0]) <= 1e-14 && Math.abs(origin[1]) <= 1e-14) {
    const sign = Math.sign(origin[2]);
    east = [0, 1, 0];
    north = [-sign, 0, 0];
    up = [0, 0, sign];
  } else {
    up = normalize([origin[0] * ONE_OVER_RADII_SQUARED[0], origin[1] * ONE_OVER_RADII_SQUARED[1], origin[2] * ONE_OVER_RADII_SQUARED[2]]);
    east = normalize([-origin[1], origin[0], 0]);
    north = cross(up, east);
  }
  return new Float64Array([...east, 0, ...north, 0, ...up, 0, origin[0], origin[1], origin[2], 1]);
}

/** Column-major 4x4 `m` applied to point `p`, and to vector `v`. */
export const transformPoint = (m: ArrayLike<number>, p: ArrayLike<number>): Vec3 => [
  m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
  m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
  m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
];
export const transformVector = (m: ArrayLike<number>, v: ArrayLike<number>): Vec3 => [
  m[0] * v[0] + m[4] * v[1] + m[8] * v[2],
  m[1] * v[0] + m[5] * v[1] + m[9] * v[2],
  m[2] * v[0] + m[6] * v[1] + m[10] * v[2],
];

/** A plane `normal · p + distance = 0`, the normal pointing to the inside. */
export interface Plane {
  normal: Vec3;
  distance: number;
}

export function planeFromPointNormal(point: ArrayLike<number>, normal: ArrayLike<number>): Plane {
  const n = normalize(normal);
  return { normal: n, distance: -dot(n, point) };
}

export const OUTSIDE = -1;
export const INTERSECTING = 0;
export const INSIDE = 1;

/** A bounding volume: an oriented box (`center`, `halfAxes` as three column vectors) or a sphere. */
export type Volume = { center: Vec3; halfAxes: [Vec3, Vec3, Vec3] } | { center: Vec3; radius: number };

export function intersectPlane(v: Volume, plane: Plane): number {
  const d = dot(plane.normal, v.center) + plane.distance;
  if ("radius" in v) return d < -v.radius ? OUTSIDE : d < v.radius ? INTERSECTING : INSIDE;
  const n = plane.normal;
  const [u, w, z] = v.halfAxes;
  const r = Math.abs(dot(n, u)) + Math.abs(dot(n, w)) + Math.abs(dot(n, z));
  return d <= -r ? OUTSIDE : d >= r ? INSIDE : INTERSECTING;
}

export function distanceSquaredTo(v: Volume, point: ArrayLike<number>): number {
  const offset = sub(point, v.center);
  if ("radius" in v) {
    const d = Math.max(0, length(offset) - v.radius);
    return d * d;
  }
  let sum = 0.0;
  for (const axis of v.halfAxes) {
    const half = length(axis);
    const d = Math.abs(dot(offset, normalize(axis))) - half;
    if (d > 0) sum += d * d;
  }
  return sum;
}

/** The culling volume's plane masks: every plane inside, outside, or not yet known. */
export const MASK_OUTSIDE = 0xffffffff;
export const MASK_INSIDE = 0x00000000;
export const MASK_INDETERMINATE = 0x7fffffff;

/** math.gl's `computeVisibilityWithPlaneMask`: the planes `v` still straddles, starting from its parent's. */
export function visibilityWithPlaneMask(planes: Plane[], v: Volume, parentMask: number): number {
  if (parentMask === MASK_OUTSIDE || parentMask === MASK_INSIDE) return parentMask;
  let mask = MASK_INSIDE;
  for (let k = 0; k < planes.length; ++k) {
    const flag = k < 31 ? 1 << k : 0;
    if (k < 31 && (parentMask & flag) === 0) continue;
    const r = intersectPlane(v, planes[k]);
    if (r === OUTSIDE) return MASK_OUTSIDE;
    if (r === INTERSECTING) mask |= flag;
  }
  return mask;
}

/** Column-major 4x4 `a` times `b`. */
export function multiply(a: ArrayLike<number>, b: ArrayLike<number>): Float64Array {
  const out = new Float64Array(16);
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) out[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3];
  }
  return out;
}

export const IDENTITY = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

/**
 * A tile's bounding volume in ECEF from its tileset JSON (`box`, `region` or `sphere`) and the tile's
 * transform, as loaders.gl's `createBoundingVolume` makes it: a region becomes the box through its
 * corners (`createObbFromRegion`) and ignores the transform.
 */
export function boundingVolume(header: Record<string, any>, transform: ArrayLike<number>): Volume {
  if (Array.isArray(header.box) && header.box.length >= 12) {
    const b = header.box;
    return {
      center: transformPoint(transform, [b[0], b[1], b[2]]),
      halfAxes: [transformVector(transform, [b[3], b[4], b[5]]), transformVector(transform, [b[6], b[7], b[8]]), transformVector(transform, [b[9], b[10], b[11]])],
    };
  }
  if (Array.isArray(header.region) && header.region.length >= 6) {
    const [west, south, east, north, minH, maxH] = header.region.map((r: number, i: number) => (i < 4 ? r * DEGREES : r));
    const nw = toCartesian(west, north, minH);
    const se = toCartesian(east, south, maxH);
    const center = scale(add(nw, se), 0.5);
    const c = toCartographic(center) ?? [0, 0, 0];
    return {
      center,
      halfAxes: [sub(toCartesian(east, c[1], c[2]), center), sub(toCartesian(c[0], north, c[2]), center), sub(toCartesian(c[0], c[1], maxH), center)],
    };
  }
  if (Array.isArray(header.sphere) && header.sphere.length >= 4) {
    const s = header.sphere;
    const sx = length([transform[0], transform[1], transform[2]]);
    const sy = length([transform[4], transform[5], transform[6]]);
    const sz = length([transform[8], transform[9], transform[10]]);
    return { center: transformPoint(transform, [s[0], s[1], s[2]]), radius: s[3] * Math.max(Math.max(sx, sy), sz) };
  }
  throw new Error("a tile's bounding volume must be a box, region or sphere");
}
