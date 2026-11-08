// Point cloud colors for mbmap/3d's point cloud and I3S layers: the file's RGB, or classes and ramps.

/** Points as decoded: f32 east, north, up meters and their per-point attributes (null when absent). */
export interface CloudPoints {
  count: number;
  positions: Float32Array;
  colors: Uint8Array | null;
  intensity: Uint16Array | null;
  classification: Uint8Array | null;
}

/** How points are colored: the file's `"rgb"` (the default when it has them), `"height"`, `"intensity"` or `"classification"` (ASPRS classes). */
export type CloudColor = "rgb" | "height" | "intensity" | "classification";

/** ASPRS classes 0 to 18 (LAS 1.4 R15 table 17) as RGB: unclassified gray, ground brown, vegetation greens, buildings orange, water blue. */
const CLASS_COLORS = [
  [150, 150, 150], [170, 170, 170], [150, 110, 70], [140, 200, 110], [70, 160, 70], [30, 110, 40], [230, 130, 60], [230, 60, 200], [160, 160, 160],
  [70, 130, 220], [200, 180, 60], [90, 90, 90], [200, 200, 200], [240, 220, 40], [240, 220, 40], [180, 60, 60], [240, 220, 40], [120, 100, 160], [230, 60, 200],
];
/** Low to high, as viridis' ends and middle. */
const RAMP = [[68, 1, 84], [59, 82, 139], [33, 145, 140], [94, 201, 98], [253, 231, 37]];

/** The RGB of each point for `mode`; heights and intensities ramp over `range`, else over the points' own. */
export function cloudColors(c: CloudPoints, mode: CloudColor | undefined, range?: [number, number]): Uint8Array {
  if ((mode ?? "rgb") === "rgb" && c.colors) return c.colors;
  const n = c.count;
  const out = new Uint8Array(3 * n);
  if (mode === "classification" && c.classification) {
    for (let i = 0; i < n; i++) out.set(CLASS_COLORS[c.classification[i]] ?? CLASS_COLORS[1], 3 * i);
    return out;
  }
  const value = mode === "intensity" && c.intensity ? (i: number) => c.intensity![i] : (i: number) => c.positions[3 * i + 2];
  let [lo, hi] = range ?? [Infinity, -Infinity];
  if (!range) {
    for (let i = 0; i < n; i++) {
      lo = Math.min(lo, value(i));
      hi = Math.max(hi, value(i));
    }
  }
  for (let i = 0; i < n; i++) {
    const t = hi > lo ? (Math.min(Math.max(value(i), lo), hi) - lo) / (hi - lo) * (RAMP.length - 1) : 0;
    const k = Math.min(Math.floor(t), RAMP.length - 2);
    const f = t - k;
    for (let j = 0; j < 3; j++) out[3 * i + j] = Math.round(RAMP[k][j] + (RAMP[k + 1][j] - RAMP[k][j]) * f);
  }
  return out;
}
