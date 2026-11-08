// Line of sight over a sampled terrain profile, with gdal_viewshed's curvature correction. Import-free, for `npm test`.

/** gdal_viewshed's default curvature coefficient (`-cc`), for light bent by the atmosphere. */
export const CURVATURE_COEFF = 0.85714;

/** The earth's radius Turf measures with, in meters. */
export const EARTH_RADIUS = 6371008.8;

/** GRS 80's and WGS 84's semi-major axis, the radius gdal_viewshed's curvature correction takes. */
export const SEMI_MAJOR = 6378137;

/** Whether the target can be seen and, when not, the first sample that hides it. */
export interface Sight {
  visible: boolean;
  blockedAt: number | null;
}

/**
 * Whether the last of `heights` (meters, `targetHeight` above it) can be seen from the first (`observerHeight`
 * above it), `distances` meters along the ground from the observer, each height lowered by the earth's
 * curvature as gdal_viewshed does (`curvatureCoeff / (2 × SEMI_MAJOR) × d²`). NaN heights hide nothing; a target 0 m away is seen.
 */
export function sight(heights: ArrayLike<number>, distances: ArrayLike<number>, observerHeight = 2, targetHeight = 0, curvatureCoeff = CURVATURE_COEFF): Sight {
  const n = heights.length;
  if (n < 2 || distances.length !== n) throw new Error("mbmap: analysis: a line of sight needs two or more samples");
  const drop = curvatureCoeff / (2 * SEMI_MAJOR);
  const z0 = heights[0] + observerHeight;
  const end = distances[n - 1];
  if (end === 0) return { visible: true, blockedAt: null };
  const target = (heights[n - 1] + targetHeight - drop * end * end - z0) / end;
  for (let i = 1; i < n - 1; i++) {
    const d = distances[i];
    const z = heights[i] - drop * d * d;
    if (d > 0 && (z - z0) / d > target) return { visible: false, blockedAt: i };
  }
  return { visible: true, blockedAt: null };
}

/** Great-circle distance in meters between two `[lng, lat]` points on Turf's sphere; mirrors `@analysis.distance`. */
export function distance(from: [number, number], to: [number, number]): number {
  const rad = (d: number) => ((d % 360) * Math.PI) / 180;
  const sLat = Math.sin(rad(to[1] - from[1]) / 2);
  const sLng = Math.sin(rad(to[0] - from[0]) / 2);
  const a = sLat * sLat + sLng * sLng * Math.cos(rad(from[1])) * Math.cos(rad(to[1]));
  return 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * EARTH_RADIUS;
}
