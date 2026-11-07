// Tiles of a `reprojected` source (npm/README.md): a WMTS tile matrix set or a GetMap of another CRS drawn on
// EPSG:3857 tiles, each pixel's center taken to the service's CRS by proj.wasm. Import-free.

const R = 6378137;
const WORLD = 2 * Math.PI * R;
const MERCATOR = new Set([3857, 900913, 3785, 102100]);
// Geographic CRSs drawn as EPSG:4326 (JGD2011 and JGD2000 lie within centimeters of it).
const LONLAT = new Set([4326, 6668, 4612]);
/** The most source tiles one tile reads, and the most pixels on a side of one GetMap. */
export const MAX_SOURCE_TILES = 64;
export const MAX_IMAGE_SIZE = 2048;
const lonOf = (mx) => (mx / R) * (180 / Math.PI);
const latOf = (my) => (Math.atan(Math.sinh(my / R)) * 180) / Math.PI;

/** Whether `spec` is a reprojected source's `{ crs, grid }` or `{ crs, image }` as the worker takes it. */
export function isReprojected(spec) {
  if (!spec || typeof spec !== "object" || !Number.isInteger(spec.crs) || spec.crs <= 0) return false;
  const { grid, image } = spec;
  if (grid !== undefined) {
    return (
      image === undefined &&
      typeof grid?.template === "string" &&
      Array.isArray(grid.matrices) &&
      grid.matrices.length > 0 &&
      grid.matrices.length <= 64 &&
      grid.matrices.every(
        (m) =>
          typeof m?.id === "string" &&
          [m.resolution, m.x, m.y, m.width, m.height, m.cols, m.rows].every(Number.isFinite) &&
          m.resolution > 0 &&
          [m.width, m.height, m.cols, m.rows].every((v) => Number.isInteger(v) && v > 0) &&
          m.width <= 4096 &&
          m.height <= 4096,
      )
    );
  }
  return typeof image?.template === "string" && typeof image.northFirst === "boolean";
}

/** `template` with its `{name}`s from `values` (percent-encoded), refused unless the result is http(s). */
export function filled(template, values) {
  const url = template.replace(/\{(\w+)\}/g, (all, name) => (name in values ? encodeURIComponent(String(values[name])).replace(/%2C/g, ",") : all));
  if (!/^https?:\/\//i.test(url)) throw new Error("reprojected tiles must be http(s) URLs");
  return url;
}

/** The matrix of `matrices` to read at `want` CRS units a tile pixel: the coarsest still finer, else the finest. */
export function matrixFor(matrices, want) {
  const finer = matrices.filter((m) => m.resolution <= want * 1.0001);
  const pick = (list, better) => list.reduce((a, b) => (better(b.resolution, a.resolution) ? b : a));
  return finer.length ? pick(finer, (b, a) => b > a) : pick(matrices, (b, a) => b < a);
}

/** The columns and rows `[c0, r0, c1, r1]` (inclusive) of matrix `m` that the box `[x0, y0, x1, y1]` meets, or null. */
export function tilesOf(m, [x0, y0, x1, y1]) {
  const w = m.resolution * m.width;
  const h = m.resolution * m.height;
  const c0 = Math.max(0, Math.floor((x0 - m.x) / w));
  const c1 = Math.min(m.cols - 1, Math.floor((x1 - m.x) / w));
  const r0 = Math.max(0, Math.floor((m.y - y1) / h));
  const r1 = Math.min(m.rows - 1, Math.floor((m.y - y0) / h));
  return c0 <= c1 && r0 <= r1 ? [c0, r0, c1, r1] : null;
}

/**
 * XYZ tile `z`/`x`/`y` of reprojected source `spec` as a PNG, or null where it shows nothing. `ctx.transform(from, to, xy)`
 * takes pairs between EPSG codes; `ctx.image(url)` gives a URL's ImageData (null for a missing tile).
 */
export async function reprojectTile(spec, { z, x, y, tileSize: size = 256 }, ctx) {
  const crs = spec.crs;
  const px = WORLD / 2 ** z / size;
  const mx0 = -WORLD / 2 + x * (WORLD / 2 ** z);
  const my0 = WORLD / 2 - y * (WORLD / 2 ** z);
  const n = size * size;
  let xy = new Float64Array(n * 2);
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      const mx = mx0 + (i + 0.5) * px;
      const my = my0 - (j + 0.5) * px;
      const k = (j * size + i) * 2;
      xy[k] = MERCATOR.has(crs) ? mx : lonOf(mx);
      xy[k + 1] = MERCATOR.has(crs) ? my : latOf(my);
    }
  }
  if (!MERCATOR.has(crs) && !LONLAT.has(crs)) {
    try {
      xy = await ctx.transform(4326, crs, xy);
    } catch (err) {
      throw new Error(`EPSG:${crs} is not drawn: ${err.message}`);
    }
  }
  const box = [Infinity, Infinity, -Infinity, -Infinity];
  for (let k = 0; k < n; k++) {
    const [fx, fy] = [xy[k * 2], xy[k * 2 + 1]];
    if (!Number.isFinite(fx) || !Number.isFinite(fy)) continue;
    box[0] = Math.min(box[0], fx);
    box[1] = Math.min(box[1], fy);
    box[2] = Math.max(box[2], fx);
    box[3] = Math.max(box[3], fy);
  }
  if (!(box[0] <= box[2])) return null;
  const c = (size / 2) * size + size / 2;
  const want = Math.hypot(xy[c * 2] - xy[c * 2 - 2], xy[c * 2 + 1] - xy[c * 2 - 1]) || (box[2] - box[0]) / size;
  // `find(fx, fy)` is the offset of the source pixel under a point in `hit`'s data, or -1.
  let hit = null;
  let find;
  if (spec.grid) {
    const m = matrixFor(spec.grid.matrices, want);
    const span = tilesOf(m, box);
    if (!span) return null;
    const [c0, r0, c1, r1] = span;
    if ((c1 - c0 + 1) * (r1 - r0 + 1) > MAX_SOURCE_TILES) return null;
    const byTile = new Map();
    const loads = [];
    for (let r = r0; r <= r1; r++) {
      for (let col = c0; col <= c1; col++) {
        const url = filled(spec.grid.template, { TileMatrix: m.id, TileRow: r, TileCol: col });
        loads.push(ctx.image(url).then((data) => data && byTile.set(r * m.cols + col, data)));
      }
    }
    await Promise.all(loads);
    find = (fx, fy) => {
      const gx = (fx - m.x) / m.resolution;
      const gy = (m.y - fy) / m.resolution;
      const col = Math.floor(gx / m.width);
      const row = Math.floor(gy / m.height);
      const data = byTile.get(row * m.cols + col);
      if (!data || col < 0 || row < 0 || col >= m.cols || row >= m.rows) return -1;
      const ix = Math.floor(gx - col * m.width);
      const iy = Math.floor(gy - row * m.height);
      if (ix >= data.width || iy >= data.height) return -1;
      hit = data;
      return (iy * data.width + ix) * 4;
    };
  } else {
    // Two and a half pixels around, so that a box in degrees puts the tile's centers mid-pixel.
    const pad = 2.5 * want;
    const [x0, y0, x1, y1] = [box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad];
    const width = Math.max(1, Math.min(MAX_IMAGE_SIZE, Math.ceil((x1 - x0) / want)));
    const height = Math.max(1, Math.min(MAX_IMAGE_SIZE, Math.ceil((y1 - y0) / want)));
    const bbox = (spec.image.northFirst ? [y0, x0, y1, x1] : [x0, y0, x1, y1]).join(",");
    const data = await ctx.image(filled(spec.image.template, { bbox, width, height }));
    if (!data) return null;
    const [rx, ry] = [(x1 - x0) / data.width, (y1 - y0) / data.height];
    hit = data;
    find = (fx, fy) => {
      const ix = Math.floor((fx - x0) / rx);
      const iy = Math.floor((y1 - fy) / ry);
      return ix >= 0 && iy >= 0 && ix < data.width && iy < data.height ? (iy * data.width + ix) * 4 : -1;
    };
  }
  const out = new Uint8ClampedArray(n * 4);
  let any = false;
  for (let k = 0; k < n; k++) {
    const at = find(xy[k * 2], xy[k * 2 + 1]);
    if (at < 0) continue;
    const src = hit.data;
    out.set(src.subarray(at, at + 4), k * 4);
    any ||= src[at + 3] > 0;
  }
  return any ? ctx.png(out, size) : null;
}
