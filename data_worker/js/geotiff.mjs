// GeoTIFFs drawn: what a source needs to know of a file, and its XYZ tiles, read through
// geotiff-read.mjs.

import { bboxOf, levels, noDataOf, open, originOf, readRaster, resolutionOf } from "./geotiff-read.mjs";

export { readRaster };

const R = 6378137;
const WORLD = 2 * Math.PI * R;
const MERCATOR = new Set([3857, 900913, 3785, 102100]);
// Geographic CRSs drawn as EPSG:4326 (JGD2011 and JGD2000 lie within centimeters of it).
const LONLAT = new Set([4326, 6668, 4612]);
const EDGE_STEPS = 32;
const lonOf = (mx) => (mx / R) * (180 / Math.PI);
const latOf = (my) => (Math.atan(Math.sinh(my / R)) * 180) / Math.PI;

// "mercator", "lonlat", or "other" for an EPSG code proj.wasm takes the pixels through.
function kindOf(crs) {
  if (MERCATOR.has(crs)) return "mercator";
  if (LONLAT.has(crs)) return "lonlat";
  if (!crs) throw new Error("a GeoTIFF without an EPSG code is not drawn");
  return "other";
}

/** The x, y pairs `xy` from EPSG:`from` to EPSG:`to` through `ctx.transform`, with the CRS named on failure. */
async function project(ctx, from, to, xy) {
  try {
    return await ctx.transform(from, to, xy);
  } catch (err) {
    throw new Error(`GeoTIFFs in EPSG:${from === 4326 ? to : from} are not drawn: ${err.message}`);
  }
}

/** The finite values of `band` but `noData`: [min, max], or null. */
function extent(band, noData) {
  let lo = Infinity;
  let hi = -Infinity;
  for (const v of band) {
    if (v === noData || !Number.isFinite(v)) continue;
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  return lo <= hi ? [lo, hi] : null;
}

/**
 * What drawing the GeoTIFF of `source` needs: `crs`, `bounds` in longitude and latitude, the
 * `maxzoom` its first image's pixels match on 256-pixel tiles, `samples`, `noData`, and `range`, the
 * finite values of band 0 in its coarsest image.
 */
export async function rasterInfo(source, ctx) {
  const { images } = await open(source, ctx);
  const first = images[0];
  const kind = kindOf(first.epsg);
  const [w, s, e, n] = bboxOf(first);
  let bounds;
  let res;
  if (kind === "other") {
    // The edges taken to longitude and latitude at EDGE_STEPS points each, and two pixels at the center.
    const [rx, ry] = resolutionOf(first);
    const [cx, cy] = [(w + e) / 2, (s + n) / 2];
    const xy = [cx, cy, cx + Math.abs(rx), cy, cx, cy + Math.abs(ry)];
    for (let i = 0; i <= EDGE_STEPS; i++) {
      const [x, y] = [w + ((e - w) * i) / EDGE_STEPS, s + ((n - s) * i) / EDGE_STEPS];
      xy.push(x, s, x, n, w, y, e, y);
    }
    const ll = await project(ctx, first.epsg, 4326, Float64Array.from(xy));
    bounds = [Infinity, Infinity, -Infinity, -Infinity];
    for (let i = 6; i < ll.length; i += 2) {
      if (Number.isNaN(ll[i]) || Number.isNaN(ll[i + 1])) continue;
      bounds = [Math.min(bounds[0], ll[i]), Math.min(bounds[1], ll[i + 1]), Math.max(bounds[2], ll[i]), Math.max(bounds[3], ll[i + 1])];
    }
    if (!(bounds[0] <= bounds[2])) throw new Error(`the GeoTIFF lies out of reach of EPSG:${first.epsg}`);
    bounds = [Math.max(-180, bounds[0]), Math.max(-85.051129, bounds[1]), Math.min(180, bounds[2]), Math.min(85.051129, bounds[3])];
    // A pixel's width in Web Mercator meters at the center: the shorter of its two sides.
    const merc = (i) => [(ll[i] * Math.PI * R) / 180, R * Math.log(Math.tan(Math.PI / 4 + (ll[i + 1] * Math.PI) / 360))];
    const [c, a, b] = [merc(0), merc(2), merc(4)];
    res = Math.min(Math.hypot(a[0] - c[0], a[1] - c[1]), Math.hypot(b[0] - c[0], b[1] - c[1]));
  } else {
    bounds = kind === "mercator" ? [lonOf(w), latOf(s), lonOf(e), latOf(n)] : [w, s, e, n];
    res = Math.abs(resolutionOf(first)[0]) * (kind === "mercator" ? 1 : (Math.PI / 180) * R);
  }
  const maxzoom = Number.isFinite(res) && res > 0 ? Math.max(0, Math.min(24, Math.ceil(Math.log2(WORLD / 256 / res) - 1e-6))) : 0;
  const coarse = levels(images)[0];
  const { bands } = await readRaster(source, { image: images.indexOf(coarse), samples: [0] }, ctx);
  return { crs: first.epsg, bounds, maxzoom, samples: first.samples, noData: noDataOf(first), range: extent(bands[0], noDataOf(first)) };
}

/** A CSS color as [r, g, b, a] (0 to 255), read through a canvas. */
function rgbaOf(color, ctx) {
  ctx.fillStyle = "#000";
  ctx.fillStyle = color;
  ctx.clearRect(0, 0, 1, 1);
  ctx.fillRect(0, 0, 1, 1);
  return Array.from(ctx.getImageData(0, 0, 1, 1).data);
}

/** XYZ tile `z`/`x`/`y` of the GeoTIFF of `source` as a PNG, or null where it has no pixel: each pixel's center
 * (taken to the file's CRS by proj.wasm unless it is EPSG:3857 or 4326) read from the coarsest image still finer
 * than the tile, colored as npm/README.md's `geotiff` sources. */
export async function renderTile(source, { z, x, y, tileSize: size = 256, bands, range, colors, dem = false, resampling }, ctx) {
  const { images } = await open(source, ctx);
  const first = images[0];
  const kind = kindOf(first.epsg);
  const px = WORLD / 2 ** z / size;
  const mx0 = -WORLD / 2 + x * (WORLD / 2 ** z);
  const my0 = WORLD / 2 - y * (WORLD / 2 ** z);
  // Each pixel's center in the file's coordinates, row by row.
  const fx = new Float64Array(size * size);
  const fy = new Float64Array(size * size);
  let want;
  if (kind === "other") {
    const ll = new Float64Array(size * size * 2);
    for (let j = 0; j < size; j++) {
      const lat = latOf(my0 - (j + 0.5) * px);
      for (let i = 0; i < size; i++) {
        ll[(j * size + i) * 2] = lonOf(mx0 + (i + 0.5) * px);
        ll[(j * size + i) * 2 + 1] = lat;
      }
    }
    const xy = await project(ctx, 4326, first.epsg, ll);
    for (let k = 0; k < size * size; k++) {
      fx[k] = xy[k * 2];
      fy[k] = xy[k * 2 + 1];
    }
    // A tile pixel's width in the file's units at the tile's center.
    const c = (size / 2) * size + size / 2;
    want = Math.hypot(fx[c] - fx[c - 1], fy[c] - fy[c - 1]);
  } else {
    for (let j = 0; j < size; j++) {
      const my = my0 - (j + 0.5) * px;
      const yy = kind === "lonlat" ? latOf(my) : my;
      for (let i = 0; i < size; i++) {
        const mx = mx0 + (i + 0.5) * px;
        fx[j * size + i] = kind === "lonlat" ? lonOf(mx) : mx;
        fy[j * size + i] = yy;
      }
    }
    want = Math.abs(fx[1] - fx[0]);
  }
  const box = bboxOf(first);
  let img = images[0];
  for (const level of levels(images)) {
    img = level;
    if (want > (box[2] - box[0]) / level.width) break;
  }
  const [ox, oy] = originOf(first);
  const [rx, ry] = resolutionOf(img, first);
  const linear = resampling === "bilinear";
  const shift = linear ? 0.5 : 0;
  const cols = Float64Array.from(fx, (v) => (v - ox) / rx - shift);
  const rows = Float64Array.from(fy, (v) => (v - oy) / ry - shift);
  const span = (a, n) => {
    let lo = Infinity;
    let hi = -Infinity;
    for (const v of a) {
      if (Number.isNaN(v)) continue;
      lo = Math.min(lo, Math.floor(v));
      hi = Math.max(hi, Math.floor(v) + (linear ? 2 : 1));
    }
    return [Math.max(0, lo), Math.min(n, hi)];
  };
  const [c0, c1] = span(cols, img.width);
  const [r0, r1] = span(rows, img.height);
  if (c0 >= c1 || r0 >= r1) return null;
  const rgb = !dem && !bands && img.samples >= 3 && img.bits.slice(0, 3).every((b) => b === 8) && img.formats[0] === 1;
  const samples = bands ?? (rgb ? (img.samples >= 4 ? [0, 1, 2, 3] : [0, 1, 2]) : [0]);
  const raster = await readRaster(source, { image: images.indexOf(img), window: [c0, r0, c1, r1], samples }, ctx);
  const w = c1 - c0;
  const noData = raster.noData;
  const canvas = new OffscreenCanvas(size, size);
  const c2d = canvas.getContext("2d", { willReadFrequently: true });
  const stops = (colors ?? []).map(([v, c]) => [v, rgbaOf(c, c2d)]).sort((a, b) => a[0] - b[0]);
  const [lo, hi] = range ?? [0, 255];
  const out = new Uint8ClampedArray(size * size * 4);
  // Band `b` at column `cx`, row `cy` of the image: NaN off the window or at no data.
  const at = (b, cx, cy) => {
    if (cx < c0 || cx >= c1 || cy < r0 || cy >= r1) return NaN;
    const v = raster.bands[b][(cy - r0) * w + cx - c0];
    return v === noData ? NaN : v;
  };
  const sample = (b, sx, sy) => {
    if (!linear) return sx >= 0 && sy >= 0 && sx < img.width && sy < img.height ? at(b, Math.floor(sx), Math.floor(sy)) : NaN;
    const [gx, gy] = [Math.floor(sx), Math.floor(sy)];
    const [tx, ty] = [sx - gx, sy - gy];
    const edge = (v, n) => Math.min(n - 1, Math.max(0, v));
    if (!(sx >= -0.5 && sy >= -0.5 && sx <= img.width - 0.5 && sy <= img.height - 0.5)) return NaN;
    const [xa, xb, ya, yb] = [edge(gx, img.width), edge(gx + 1, img.width), edge(gy, img.height), edge(gy + 1, img.height)];
    const v = (1 - ty) * ((1 - tx) * at(b, xa, ya) + tx * at(b, xb, ya)) + ty * ((1 - tx) * at(b, xa, yb) + tx * at(b, xb, yb));
    return v;
  };
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      const k = j * size + i;
      const o = k * 4;
      const v = sample(0, cols[k], rows[k]);
      if (dem) {
        const e = Math.min(65535.99, Math.max(0, (Number.isNaN(v) ? 0 : v) + 32768));
        out[o] = Math.floor(e / 256);
        out[o + 1] = Math.floor(e) % 256;
        out[o + 2] = Math.floor((e - Math.floor(e)) * 256);
        out[o + 3] = 255;
        continue;
      }
      if (Number.isNaN(v)) continue;
      if (rgb) {
        out[o] = v;
        out[o + 1] = sample(1, cols[k], rows[k]);
        out[o + 2] = sample(2, cols[k], rows[k]);
        out[o + 3] = samples.length === 4 ? sample(3, cols[k], rows[k]) : 255;
        continue;
      }
      if (stops.length > 0) {
        let k = 0;
        while (k < stops.length - 1 && v > stops[k + 1][0]) k++;
        const [va, ca] = stops[k];
        const [vb, cb] = stops[Math.min(k + 1, stops.length - 1)];
        const t = vb > va ? Math.min(1, Math.max(0, (v - va) / (vb - va))) : 0;
        for (let q = 0; q < 4; q++) out[o + q] = Math.round(ca[q] + (cb[q] - ca[q]) * t);
        continue;
      }
      const g = Math.round((hi > lo ? Math.min(1, Math.max(0, (v - lo) / (hi - lo))) : 0) * 255);
      out[o] = out[o + 1] = out[o + 2] = g;
      out[o + 3] = 255;
    }
  }
  c2d.putImageData(new ImageData(out, size, size), 0, 0);
  return (await canvas.convertToBlob({ type: "image/png" })).arrayBuffer();
}
