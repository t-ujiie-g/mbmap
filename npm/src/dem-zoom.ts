// The DEM zoom `sampleDem` loads: the deepest whose tiles over the bounds fit
// one grid. Import-free, so that `npm test` can load it.

/** Largest grid side in cells (`MAX_GRID_SIDE`, analysis_worker/dem.mbt). */
export const MAX_GRID_SIDE = 4096;

/** The tile columns or rows `[first, last]` that cover `[a, b]` at zoom `z` (Web Mercator, latitudes clamped). */
function tileSpan(z: number, a: number, b: number, lat: boolean): number {
  const n = 2 ** z;
  const t = (v: number) => {
    if (!lat) return Math.floor(((v + 180) / 360) * n);
    const s = Math.sin((Math.max(-85.0511, Math.min(85.0511, v)) * Math.PI) / 180);
    return Math.floor((0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * n);
  };
  const clamp = (i: number) => Math.min(n - 1, Math.max(0, i));
  return Math.abs(clamp(t(b)) - clamp(t(a))) + 1;
}

/**
 * The deepest zoom up to `maxZoom` (0 to 24) at which the tiles covering `bounds` make at most
 * `MAX_GRID_SIDE` cells a side; `tileSize` is 256 to 4096 pixels.
 */
export function demZoom(bounds: [number, number, number, number], maxZoom: number, tileSize = 256): number {
  if (!(tileSize >= 256 && tileSize <= MAX_GRID_SIDE)) throw new Error(`mbmap: analysis: tileSize must be 256 to ${MAX_GRID_SIDE}: ${tileSize}`);
  const most = Math.floor(MAX_GRID_SIDE / tileSize);
  for (let z = Math.floor(Math.min(24, maxZoom)); z > 0; z--) {
    if (tileSpan(z, bounds[0], bounds[2], false) <= most && tileSpan(z, bounds[1], bounds[3], true) <= most) return z;
  }
  return 0;
}
