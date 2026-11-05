// GeoTIFF and COG windows read as geotiff 3.0.5's `readRasters` reads them (MIT License, Copyright
// (c) 2015 EOX IT Services GmbH; see NOTICE): which image, which window, which blocks (by range
// requests from a URL), and the blocks the host decodes; geotiff.wasm does the rest. Import-free.

// What a first range request asks for, as geotiff's BlockedSource blocks.
const FIRST_BYTES = 65536;
// Requests for blocks this close together are merged.
const GAP_BYTES = 65536;
const PARALLEL = 6;
// A read's blocks may decode to this many times `ctx.max`: a window's bands are at most that, and
// its blocks hold more where they overhang it or carry other samples.
const DECODED_RATIO = 8;
const ARRAYS = {
  "1:1": Uint8Array, "1:2": Uint16Array, "1:4": Uint32Array,
  "2:1": Int8Array, "2:2": Int16Array, "2:4": Int32Array,
  "3:4": Float32Array, "3:8": Float64Array,
};

/** The images of a "GeoTIFF images" summary (docs/FORMATS.md). */
export function readSummary(buffer) {
  const v = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  let at = 0;
  const u32 = () => ((at += 4), v.getUint32(at - 4, true));
  const i32 = () => ((at += 4), v.getInt32(at - 4, true));
  const doubles = () => {
    const n = u32();
    const out = new Float64Array(n);
    for (let i = 0; i < n; i++) out[i] = v.getFloat64(at + i * 8, true);
    at += n * 8;
    return out;
  };
  const little = u32() === 1;
  const images = Array.from({ length: u32() }, () => {
    const [width, height, tiled, blockWidth, blockHeight, samples, planar, compression, predictor, photometric, subfile, oldSubfile, epsg, rasterType] = Array.from({ length: 14 }, i32);
    const bits = [];
    const formats = [];
    for (let i = 0; i < samples; i++) {
      bits.push(u32());
      formats.push(u32());
    }
    const [pixelScale, tiepoint, transform, offsets, counts] = [doubles(), doubles(), doubles(), doubles(), doubles()];
    let nodata = null;
    if (bytes[at++] === 1) {
      const n = u32();
      nodata = new TextDecoder().decode(bytes.subarray(at, at + n));
      at += n;
    }
    const tables = i32();
    const jpegTables = tables >= 0 ? bytes.slice(at, at + tables) : null;
    at += Math.max(0, tables);
    at = (at + 3) & ~3;
    return { width, height, tiled: tiled === 1, blockWidth, blockHeight, samples, bits, formats, planar, compression, predictor, photometric, subfile, oldSubfile, epsg, rasterType, pixelScale, tiepoint, transform, offsets, counts, nodata, jpegTables };
  });
  return { little, images };
}

/** geotiff's `getGDALNoData`: the GDAL_NODATA text without its last character, as a number. */
export const noDataOf = (img) => (img.nodata ? Number(img.nodata.substring(0, img.nodata.length - 1)) : null);

/** geotiff's `getOrigin`. */
export function originOf(img) {
  if (img.tiepoint.length === 6) return [img.tiepoint[3], img.tiepoint[4], img.tiepoint[5]];
  const t = img.transform;
  if (t.length >= 12) return [t[3], t[7], t[11]];
  throw new Error("The image does not have an affine transformation.");
}

/** geotiff's `getResolution`, `ref` the first image for an overview without geo tags. */
export function resolutionOf(img, ref = null) {
  const s = img.pixelScale;
  if (s.length >= 3) return [s[0], -s[1], s[2]];
  const t = img.transform;
  if (t.length >= 11) {
    if (t[1] === 0 && t[4] === 0) return [t[0], -t[5], t[10]];
    return [Math.sqrt(t[0] * t[0] + t[4] * t[4]), -Math.sqrt(t[1] * t[1] + t[5] * t[5]), t[10]];
  }
  if (ref) {
    const [x, y, z] = resolutionOf(ref);
    return [(x * ref.width) / img.width, (y * ref.height) / img.height, (z * ref.width) / img.width];
  }
  throw new Error("The image does not have an affine transformation.");
}

/** geotiff's `getBoundingBox`. */
export function bboxOf(img) {
  const t = img.transform;
  if (t.length >= 8) {
    const [a, b, , d, e, f, , h] = t;
    const xs = [];
    const ys = [];
    for (const [i, j] of [[0, 0], [0, img.height], [img.width, 0], [img.width, img.height]]) {
      xs.push(d + a * i + b * j);
      ys.push(h + e * i + f * j);
    }
    return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
  }
  const [x1, y1] = originOf(img);
  const [rx, ry] = resolutionOf(img);
  const [x2, y2] = [x1 + rx * img.width, y1 + ry * img.height];
  return [Math.min(x1, x2), Math.min(y1, y2), Math.max(x1, x2), Math.max(y1, y2)];
}

/**
 * The image and window geotiff's `GeoTIFF.readRasters` reads for `options` (`window`, `bbox`,
 * `width`, `height`, `resX`, `resY`; `image` picks an image by index instead).
 */
export function choose(images, options) {
  const first = images[0];
  const { window: given, width, height, image } = options;
  let { resX, resY, bbox } = options;
  if (given && bbox) throw new Error('Both "bbox" and "window" passed.');
  let used = first;
  if (image !== undefined) {
    if (!Number.isInteger(image) || image < 0 || image >= images.length) throw new Error(`no image ${image}`);
    used = images[image];
  } else {
    if (width || height) {
      if (given) {
        const [ox, oy] = originOf(first);
        const [rx, ry] = resolutionOf(first);
        bbox = [ox + given[0] * rx, oy + given[1] * ry, ox + given[2] * rx, oy + given[3] * ry];
      }
      const box = bbox || bboxOf(first);
      if (width) {
        if (resX) throw new Error("Both width and resX passed");
        resX = (box[2] - box[0]) / width;
      }
      if (height) {
        if (resY) throw new Error("Both width and resY passed");
        resY = (box[3] - box[1]) / height;
      }
    }
    if (resX || resY) {
      const box = bboxOf(first);
      const all = images.filter((img, i) => i === 0 || img.oldSubfile === 2 || (img.subfile & 1));
      all.sort((a, b) => a.width - b.width);
      for (const img of all) {
        used = img;
        if ((resX && resX > (box[2] - box[0]) / img.width) || (resY && resY > (box[3] - box[1]) / img.height)) break;
      }
    }
  }
  let wnd = given ?? [0, 0, used.width, used.height];
  if (bbox) {
    const [ox, oy] = originOf(first);
    const [rx, ry] = resolutionOf(used, first);
    const w = [Math.round((bbox[0] - ox) / rx), Math.round((bbox[1] - oy) / ry), Math.round((bbox[2] - ox) / rx), Math.round((bbox[3] - oy) / ry)];
    wnd = [Math.min(w[0], w[2]), Math.min(w[1], w[3]), Math.max(w[0], w[2]), Math.max(w[1], w[3])];
  }
  if (wnd[0] > wnd[2] || wnd[1] > wnd[3]) throw new Error("Invalid subsets");
  return { index: images.indexOf(used), window: wnd };
}

/** geotiff's `resampleNearest` and `resampleBilinear` of each band. */
export function resample(bands, inWidth, inHeight, outWidth, outHeight, method = "nearest") {
  const relX = inWidth / outWidth;
  const relY = inHeight / outHeight;
  const m = String(method).toLowerCase();
  if (m !== "nearest" && m !== "bilinear" && m !== "linear") throw new Error(`Unsupported resampling method: '${method}'`);
  const lerp = (a, b, t) => (1 - t) * a + t * b;
  return bands.map((band) => {
    const out = new band.constructor(outWidth * outHeight);
    for (let y = 0; y < outHeight; ++y) {
      if (m === "nearest") {
        const cy = Math.min(Math.round(relY * y), inHeight - 1);
        for (let x = 0; x < outWidth; ++x) out[y * outWidth + x] = band[cy * inWidth + Math.min(Math.round(relX * x), inWidth - 1)];
        continue;
      }
      const rawY = relY * y;
      const yl = Math.floor(rawY);
      const yh = Math.min(Math.ceil(rawY), inHeight - 1);
      for (let x = 0; x < outWidth; ++x) {
        const rawX = relX * x;
        const xl = Math.floor(rawX);
        const xh = Math.min(Math.ceil(rawX), inWidth - 1);
        const v = lerp(lerp(band[yl * inWidth + xl], band[yl * inWidth + xh], rawX % 1), lerp(band[yh * inWidth + xl], band[yh * inWidth + xh], rawX % 1), rawY % 1);
        out[y * outWidth + x] = v;
      }
    }
    return out;
  });
}

/** `bytes` inflated (zlib, TIFF compression 8 and 32946), at most `max` bytes. */
async function inflate(bytes, max) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
  const reader = stream.getReader();
  const out = new Uint8Array(max);
  let n = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    const take = Math.min(value.length, max - n);
    out.set(value.subarray(0, take), n);
    n += take;
    if (n === max) {
      reader.cancel();
      break;
    }
  }
  return out.subarray(0, n);
}

/** A JPEG tile with the image's JPEGTables (its tables without their EOI, then the tile without its SOI). */
function withTables(tile, tables) {
  if (!tables || tables.length < 4) return tile;
  const out = new Uint8Array(tables.length - 2 + tile.length - 2);
  out.set(tables.subarray(0, tables.length - 2));
  out.set(tile.subarray(2), tables.length - 2);
  return out;
}

/**
 * A JPEG or WebP block decoded by the host into `samples` bytes per pixel, as geotiff's WebImageDecoder
 * does; a picture larger than the blocks of `img` is refused.
 */
async function webImage(bytes, samples, img) {
  const bitmap = await createImageBitmap(new Blob([bytes]));
  if (bitmap.width > img.blockWidth || bitmap.height > img.blockHeight) {
    bitmap.close();
    throw new Error(`malformed TIFF: a block's picture of ${bitmap.width} x ${bitmap.height} pixels`);
  }
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  const ctx = canvas.getContext("2d");
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close();
  const rgba = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
  if (samples === 4) return new Uint8Array(rgba.buffer);
  if (samples !== 3 && samples !== 1) throw new Error(`Unsupported SamplesPerPixel value: ${samples}`);
  const out = new Uint8Array((rgba.length / 4) * samples);
  for (let i = 0, j = 0; j < rgba.length; i += samples, j += 4) for (let k = 0; k < samples; k++) out[i + k] = rgba[j + k];
  return out;
}

const rowBytes = (width, bits) => Math.ceil((width * bits) / 8);

/**
 * A window of the GeoTIFF read through `source`, as `readRaster` gives it (npm/README.md):
 * `source.read(offset, length)` resolves to those bytes of the file (fewer at its end) or, from
 * a server that ignores ranges, to `{ whole }`; `source.bytes` is the file when it is at hand.
 * `wasm` is geotiff.wasm's exports with `input` and `output` (data_worker/js/read.mjs).
 */
// The first bytes (or the whole) of files read by URL, and their blocks, kept for the next reads
// (a map's tiles read the same file over and over): most recent last.
const HEADS = 8;
const BLOCK_BYTES = 32 * 1024 * 1024;
const heads = new Map();
const blocksKept = new Map();
let headTotal = 0;
let blockTotal = 0;

// The newest stays whatever its size, or a server without ranges would send its file for each read.
function keepHead(key, kept, max) {
  headTotal += kept.head.length - (heads.get(key)?.head.length ?? 0);
  heads.delete(key);
  heads.set(key, kept);
  for (const [k, { head }] of heads) {
    if (k === key || (heads.size <= HEADS && headTotal <= max)) break;
    heads.delete(k);
    headTotal -= head.length;
  }
}

function keepBlock(key, bytes) {
  if (bytes.length > BLOCK_BYTES / 8) return;
  blocksKept.set(key, bytes.slice());
  blockTotal += bytes.length;
  for (const [k, b] of blocksKept) {
    if (blockTotal <= BLOCK_BYTES) break;
    blocksKept.delete(k);
    blockTotal -= b.length;
  }
}

/**
 * The image directories of the file `source` reads, parsed into geotiff.wasm (which keeps the
 * last file's images for `window`), read again with more bytes while they reach past those read.
 */
async function open(source, { wasm, input, output, max }) {
  const kept = source.key && heads.get(source.key);
  let file = kept ? kept.file : (source.bytes ?? null);
  let head = kept ? kept.head : (file ?? (await source.read(0, FIRST_BYTES)));
  if (head.whole) file = head = head.whole;
  for (let tries = 0; ; tries++) {
    input(wasm, [head]);
    const n = wasm.parse();
    if (n !== -3) {
      const summary = readSummary(output(wasm, n));
      if (source.key) keepHead(source.key, { head, file }, max);
      return { images: summary.images, file };
    }
    const need = wasm.need();
    if (file || tries > 12 || need > max || need <= head.length) throw new Error("malformed TIFF: its image directories reach past its end");
    head = await source.read(0, Math.min(max, Math.max(Math.ceil(need) + FIRST_BYTES, head.length * 2)));
    if (!head.whole && head.length < need) throw new Error("malformed TIFF: its image directories reach past its end");
    if (head.whole) file = head = head.whole;
  }
}

export async function readRaster(source, options, ctx) {
  const { wasm, input, output, max } = ctx;
  let { images, file } = await open(source, ctx);
  const { index, window: wnd } = choose(images, options);
  const img = images[index];
  const samples = options.samples?.length ? options.samples : Array.from({ length: img.samples }, (_, i) => i);
  for (const s of samples) if (!Number.isInteger(s) || s < 0 || s >= img.samples) throw new RangeError(`Invalid sample index '${s}'.`);
  const fill = typeof options.fillValue === "number" ? options.fillValue : 0;
  input(wasm, [new Uint8Array(Uint32Array.from(samples).buffer)]);
  output(wasm, wasm.window(index, wnd[0], wnd[1], wnd[2], wnd[3], fill), true);
  // The blocks the window meets, as geotiff's `_readRaster` walks them.
  const across = Math.ceil(img.width / img.blockWidth);
  const down = Math.ceil(img.height / img.blockHeight);
  const blocks = [];
  for (let y = Math.max(Math.floor(wnd[1] / img.blockHeight), 0); y < Math.min(Math.ceil(wnd[3] / img.blockHeight), down); y++) {
    for (let x = Math.max(Math.floor(wnd[0] / img.blockWidth), 0); x < Math.min(Math.ceil(wnd[2] / img.blockWidth), across); x++) {
      for (const s of img.planar === 2 ? [...new Set(samples)] : [0]) blocks.push(s * across * down + y * across + x);
    }
  }
  const noData = noDataOf(img);
  const bits = img.planar === 2 ? null : img.bits.reduce((a, b) => a + b, 0);
  const rawSize = (i) => rowBytes(img.blockWidth, bits ?? img.bits[Math.floor(i / (across * down))]) * img.blockHeight;
  let decodedBytes = 0;
  const add = async (i, bytes) => {
    decodedBytes += rawSize(i);
    if (decodedBytes > max * DECODED_RATIO) throw new Error(`blocks decoding to more than ${max * DECODED_RATIO} bytes`);
    const c = img.compression;
    if (c === 1 || c === 5 || c === 32773) return output(wasm, (input(wasm, [bytes]), wasm.block(i, 0)), true);
    let decoded;
    if (c === 8 || c === 32946) decoded = await inflate(bytes, rawSize(i));
    else if (c === 7) decoded = await webImage(withTables(bytes, img.jpegTables), img.planar === 2 ? 1 : img.samples, img);
    else if (c === 50001) decoded = await webImage(bytes, img.planar === 2 ? 1 : img.samples, img);
    else throw new Error(`Unknown compression method identifier: ${c}`);
    input(wasm, [decoded]);
    output(wasm, wasm.block(i, 1), true);
  };
  // Block byte ranges, merged where they lie close together and read a few at a time.
  const ranges = [];
  for (const i of blocks) {
    const [offset, count] = [img.offsets[i], img.counts[i]];
    if (count === 0) {
      output(wasm, wasm.empty(i, noData || 0), true);
      continue;
    }
    const kept = !file && source.key && blocksKept.get(`${source.key}#${offset}`);
    if (kept) {
      await add(i, kept);
      continue;
    }
    if (count > max) throw new Error(`a block of ${count} bytes`);
    const last = ranges.at(-1);
    if (!file && last && offset >= last.end && offset - last.end <= GAP_BYTES && offset + count - last.start <= max) {
      last.end = Math.max(last.end, offset + count);
      last.blocks.push(i);
    } else ranges.push({ start: offset, end: offset + count, blocks: [i] });
  }
  let fetched = 0;
  for (let k = 0; k < ranges.length; k += PARALLEL) {
    const part = ranges.slice(k, k + PARALLEL);
    const got = await Promise.all(part.map(async (r) => {
      if (file) return file;
      fetched += r.end - r.start;
      if (fetched > max) throw new Error(`data larger than ${max} bytes`);
      const b = await source.read(r.start, r.end - r.start);
      if (b.whole) {
        file = b.whole;
        return file;
      }
      return b;
    }));
    for (let j = 0; j < part.length; j++) {
      const base = got[j] === file ? 0 : part[j].start;
      for (const i of part[j].blocks) {
        const at = img.offsets[i] - base;
        const bytes = got[j].subarray(at, at + img.counts[i]);
        if (bytes.length < img.counts[i]) throw new Error("malformed TIFF: a block past the end of the file");
        if (got[j] !== file && source.key) keepBlock(`${source.key}#${img.offsets[i]}`, bytes);
        await add(i, bytes);
      }
    }
  }
  const out = output(wasm, wasm.bands());
  let width = wnd[2] - wnd[0];
  let height = wnd[3] - wnd[1];
  let at = 0;
  let bands = samples.map((s) => {
    const size = img.formats[s] === 3 ? (img.bits[s] === 64 ? 8 : 4) : img.bits[s] <= 8 ? 1 : img.bits[s] <= 16 ? 2 : 4;
    const band = new ARRAYS[`${img.formats[s]}:${size}`](out, at, width * height);
    at += Math.ceil((width * height * size) / 8) * 8;
    return band;
  });
  const first = images[0];
  if ((options.width && options.width !== width) || (options.height && options.height !== height)) {
    const [w, h] = [options.width ?? width, options.height ?? height];
    bands = resample(bands, width, height, w, h, options.resampleMethod);
    [width, height] = [w, h];
  }
  // The window's corners through the first image's ModelTransformation (scaled to an overview),
  // else its origin and resolution; null without geo tags.
  let bbox = null;
  let resolution = null;
  const t = first.transform;
  const geo = t.length >= 8 || (first.tiepoint.length === 6 && first.pixelScale.length >= 3);
  if (geo) {
    const [ox, oy] = originOf(first);
    const [rx, ry] = resolutionOf(img, first);
    const k = [first.width / img.width, first.height / img.height];
    const place = t.length >= 8 ? ([i, j]) => [t[3] + t[0] * i * k[0] + t[1] * j * k[1], t[7] + t[4] * i * k[0] + t[5] * j * k[1]] : ([i, j]) => [ox + i * rx, oy + j * ry];
    const corners = [[wnd[0], wnd[1]], [wnd[2], wnd[1]], [wnd[0], wnd[3]], [wnd[2], wnd[3]]].map(place);
    const xs = corners.map((c) => c[0]);
    const ys = corners.map((c) => c[1]);
    bbox = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
    resolution = [((wnd[2] - wnd[0]) * rx) / width, ((wnd[3] - wnd[1]) * ry) / height];
  }
  return {
    width,
    height,
    bands,
    bbox,
    resolution,
    window: wnd,
    image: index,
    images: images.length,
    crs: first.epsg || null,
    pixelIsPoint: first.rasterType === 2,
    noData,
  };
}

const R = 6378137;
const WORLD = 2 * Math.PI * R;
const MERCATOR = new Set([3857, 900913, 3785, 102100]);
// Geographic CRSs drawn as EPSG:4326 (JGD2011 and JGD2000 lie within centimeters of it).
const LONLAT = new Set([4326, 6668, 4612]);
const EDGE_STEPS = 32;

// "mercator", "lonlat", or "other" for an EPSG code proj.wasm takes the pixels through.
function kindOf(crs) {
  if (MERCATOR.has(crs)) return "mercator";
  if (LONLAT.has(crs)) return "lonlat";
  if (!crs) throw new Error("a GeoTIFF without an EPSG code is not drawn");
  return "other";
}

/** `xy` (longitude, latitude pairs) in EPSG:`crs` through `ctx.transform`, with the CRS named on failure. */
async function project(ctx, from, to, xy) {
  try {
    return await ctx.transform(from, to, xy);
  } catch (err) {
    throw new Error(`GeoTIFFs in EPSG:${from === 4326 ? to : from} are not drawn: ${err.message}`);
  }
}

/** The images a resolution picks from (geotiff's: the first, and reduced-resolution ones), coarsest first. */
const levels = (images) => images.filter((img, i) => i === 0 || img.oldSubfile === 2 || (img.subfile & 1)).sort((a, b) => a.width - b.width);

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
  const toLat = (y) => (Math.atan(Math.sinh(y / R)) * 180) / Math.PI;
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
    bounds = kind === "mercator" ? [(w / R) * (180 / Math.PI), toLat(s), (e / R) * (180 / Math.PI), toLat(n)] : [w, s, e, n];
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
export async function renderTile(source, { z, x, y, tileSize = 256, bands, range, colors, dem = false, resampling }, ctx) {
  const { images } = await open(source, ctx);
  const first = images[0];
  const kind = kindOf(first.epsg);
  const size = tileSize;
  const px = WORLD / 2 ** z / size;
  const mx0 = -WORLD / 2 + x * (WORLD / 2 ** z);
  const my0 = WORLD / 2 - y * (WORLD / 2 ** z);
  const lonOf = (mx) => (mx / R) * (180 / Math.PI);
  const latOf = (my) => (Math.atan(Math.sinh(my / R)) * 180) / Math.PI;
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
