// The frame state 3D Tiles are selected with, from the map's camera: the inverse of a custom layer's
// matrix, Web Mercator's (0 to 1, height in the same units) or the globe's unit sphere, gives the eye,
// the view's center and the frustum's corners, which go to ECEF meters.
import { cross, dot, GLOBE_RADIUS, MERCATOR_RADIUS, normalize, planeFromPointNormal, scale, sub, toCartesian, type Plane, type Vec3 } from "./geo.ts";
import type { FrameState } from "./tileset.ts";

/** Column-major 4x4 inverse of `m`, or null when singular. */
export function invert(m: ArrayLike<number>): Float64Array | null {
  const [a00, a01, a02, a03, a10, a11, a12, a13, a20, a21, a22, a23, a30, a31, a32, a33] = Array.from({ length: 16 }, (_, i) => m[i]);
  const b00 = a00 * a11 - a01 * a10;
  const b01 = a00 * a12 - a02 * a10;
  const b02 = a00 * a13 - a03 * a10;
  const b03 = a01 * a12 - a02 * a11;
  const b04 = a01 * a13 - a03 * a11;
  const b05 = a02 * a13 - a03 * a12;
  const b06 = a20 * a31 - a21 * a30;
  const b07 = a20 * a32 - a22 * a30;
  const b08 = a20 * a33 - a23 * a30;
  const b09 = a21 * a32 - a22 * a31;
  const b10 = a21 * a33 - a23 * a31;
  const b11 = a22 * a33 - a23 * a32;
  const det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
  if (!det) return null;
  const d = 1 / det;
  return new Float64Array([
    (a11 * b11 - a12 * b10 + a13 * b09) * d, (a02 * b10 - a01 * b11 - a03 * b09) * d, (a31 * b05 - a32 * b04 + a33 * b03) * d, (a22 * b04 - a21 * b05 - a23 * b03) * d,
    (a12 * b08 - a10 * b11 - a13 * b07) * d, (a00 * b11 - a02 * b08 + a03 * b07) * d, (a32 * b02 - a30 * b05 - a33 * b01) * d, (a20 * b05 - a22 * b02 + a23 * b01) * d,
    (a10 * b10 - a11 * b08 + a13 * b06) * d, (a01 * b08 - a00 * b10 - a03 * b06) * d, (a30 * b04 - a31 * b02 + a33 * b00) * d, (a21 * b02 - a20 * b04 - a23 * b00) * d,
    (a11 * b07 - a10 * b09 - a12 * b06) * d, (a00 * b09 - a01 * b07 + a02 * b06) * d, (a31 * b01 - a30 * b03 - a32 * b00) * d, (a20 * b03 - a21 * b01 + a22 * b00) * d,
  ]);
}

const apply = (m: ArrayLike<number>, v: number[]): number[] => [0, 1, 2, 3].map((r) => m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] * v[3]);

/** Web Mercator (0 to 1, height in units of the world at latitude `lat0`) to ECEF meters. */
function mercatorToEcef(p: ArrayLike<number>, lat0: number): Vec3 {
  const lng = p[0] * 360 - 180;
  const lat = (Math.atan(Math.sinh(Math.PI * (1 - 2 * p[1]))) * 180) / Math.PI;
  return toCartesian(lng, lat, p[2] * 2 * Math.PI * MERCATOR_RADIUS * Math.cos((lat0 * Math.PI) / 180));
}

/** MapLibre's unit sphere (x east at longitude 90°, y north, z at longitude 0) to ECEF meters. */
function sphereToEcef(p: ArrayLike<number>): Vec3 {
  const r = Math.hypot(p[0], p[1], p[2]);
  const lng = (Math.atan2(p[0], p[2]) * 180) / Math.PI;
  const lat = (Math.asin(Math.max(-1, Math.min(1, p[1] / r))) * 180) / Math.PI;
  return toCartesian(lng, lat, (r - 1) * GLOBE_RADIUS);
}

/**
 * The frame state of the view `matrix` (clip space from Web Mercator, or from the unit sphere with
 * `globe`) draws, on a screen `width` x `height` CSS pixels; null if the matrix cannot be inverted.
 */
export function frameState(matrix: ArrayLike<number>, height: number, globe = false, width = height): FrameState | null {
  const inv = invert(matrix);
  if (!inv) return null;
  const at = (x: number, y: number, z: number): number[] => {
    const v = apply(inv, [x, y, z, 1]);
    return [v[0] / v[3], v[1] / v[3], v[2] / v[3]];
  };
  const eyeH = apply(inv, [0, 0, -1, 0]);
  const eyeRaw = [eyeH[0] / eyeH[3], eyeH[1] / eyeH[3], eyeH[2] / eyeH[3]];
  // Heights are in units of the world at the map's center, where the view's axis meets the ground.
  const nearCenterRaw = at(0, 0, -1);
  const farCenterRaw = at(0, 0, 1);
  const t = nearCenterRaw[2] / (nearCenterRaw[2] - farCenterRaw[2]);
  const centerY = Number.isFinite(t) ? nearCenterRaw[1] + (farCenterRaw[1] - nearCenterRaw[1]) * t : nearCenterRaw[1];
  const lat0 = globe ? 0 : (Math.atan(Math.sinh(Math.PI * (1 - 2 * centerY))) * 180) / Math.PI;
  const ecef = (p: number[]): Vec3 => (globe ? sphereToEcef(p) : mercatorToEcef(p, lat0));
  const eye = ecef(eyeRaw);
  const nearCenter = ecef(nearCenterRaw);
  const farCenter = ecef(farCenterRaw);
  const direction = normalize(sub(nearCenter, eye));
  const top = sub(ecef(at(0, 1, -1)), nearCenter);
  const up = normalize(sub(top, scale(direction, dot(top, direction))));
  const corners = [at(-1, -1, -1), at(1, -1, -1), at(1, 1, -1), at(-1, 1, -1)].map(ecef);
  const planes: Plane[] = [planeFromPointNormal(nearCenter, direction), planeFromPointNormal(farCenter, scale(direction, -1))];
  for (let i = 0; i < 4; i++) {
    let n = cross(sub(corners[i], eye), sub(corners[(i + 1) % 4], eye));
    if (dot(n, direction) < 0) n = scale(n, -1);
    planes.push(planeFromPointNormal(eye, n));
  }
  return { position: eye, direction, up, planes, height, sseDenominator: 1.15, view: { matrix, globe, lat0, width } };
}
