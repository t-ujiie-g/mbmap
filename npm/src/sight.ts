// Line of sight over a sampled terrain profile, with gdal_viewshed's curvature correction. Import-free, for `npm test`.

/** gdal_viewshed's default curvature coefficient (`-cc`), for light bent by the atmosphere. */
export const CURVATURE_COEFF = 0.85714;

/** The earth's radius Turf measures with, in meters. */
export const EARTH_RADIUS = 6371008.8;

/** Whether the target can be seen and, when not, the first sample that hides it. */
export interface Sight {
  visible: boolean;
  blockedAt: number | null;
}

/**
 * Whether the last of `heights` (meters, `targetHeight` above it) can be seen from the first (`observerHeight`
 * above it), `distances` meters along the ground from the observer, each height lowered by the earth's
 * curvature as gdal_viewshed lowers it (`curvatureCoeff / (2 × 6378137) × d²`). NaN heights hide nothing.
 */
export function sight(heights: ArrayLike<number>, distances: ArrayLike<number>, observerHeight = 2, targetHeight = 0, curvatureCoeff = CURVATURE_COEFF): Sight {
  const n = heights.length;
  if (n < 2 || distances.length !== n) throw new Error("mbmap: analysis: a line of sight needs two or more samples");
  const drop = curvatureCoeff / (2 * 6378137);
  const z0 = heights[0] + observerHeight;
  const end = distances[n - 1];
  const target = (heights[n - 1] + targetHeight - drop * end * end - z0) / end;
  for (let i = 1; i < n - 1; i++) {
    const d = distances[i];
    const z = heights[i] - drop * d * d;
    if (d > 0 && (z - z0) / d > target) return { visible: false, blockedAt: i };
  }
  return { visible: true, blockedAt: null };
}

/** Meters along the ground between two `[lng, lat]`, on Turf's sphere (haversine). */
export function groundDistance([x0, y0]: [number, number], [x1, y1]: [number, number]): number {
  const r = Math.PI / 180;
  const a = Math.sin(((y1 - y0) * r) / 2) ** 2 + Math.cos(y0 * r) * Math.cos(y1 * r) * Math.sin(((x1 - x0) * r) / 2) ** 2;
  return 2 * EARTH_RADIUS * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
