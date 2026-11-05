// GeoTIFF and COG windows read as geotiff 3.0.5's `readRasters` reads them: which image (by
// resolution), which window (by bbox), which blocks (by range requests from a URL), and the
// blocks the host decodes (Deflate, JPEG, WebP); geotiff.wasm does the rest. Import-free.

// What a first range request asks for, as geotiff's BlockedSource blocks.
const FIRST_BYTES = 65536;
// Requests for blocks this close together are merged.
const GAP_BYTES = 65536;
const PARALLEL = 6;
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

/** A JPEG or WebP block decoded by the host into `samples` bytes per pixel, as geotiff's WebImageDecoder does. */
async function webImage(bytes, samples) {
  const bitmap = await createImageBitmap(new Blob([bytes]));
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
export async function readRaster(source, options, { wasm, input, output, max }) {
  // The image directories, read again with more bytes while they reach past them.
  let file = source.bytes ?? null;
  let head = file ?? (await source.read(0, FIRST_BYTES));
  if (head.whole) file = head = head.whole;
  let summary;
  for (let tries = 0; ; tries++) {
    input(wasm, [head]);
    const n = wasm.parse();
    if (n !== -3) {
      summary = readSummary(output(wasm, n));
      break;
    }
    const need = wasm.need();
    if (file || tries > 12 || need > max || need <= head.length) throw new Error("malformed TIFF: its image directories reach past its end");
    head = await source.read(0, Math.min(max, Math.max(Math.ceil(need) + FIRST_BYTES, head.length * 2)));
    if (!head.whole && head.length < need) throw new Error("malformed TIFF: its image directories reach past its end");
    if (head.whole) file = head = head.whole;
  }
  const { images } = summary;
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
  const add = async (i, bytes) => {
    const c = img.compression;
    if (c === 1 || c === 5 || c === 32773) return output(wasm, (input(wasm, [bytes]), wasm.block(i, 0)), true);
    let decoded;
    if (c === 8 || c === 32946) decoded = await inflate(bytes, rawSize(i));
    else if (c === 7) decoded = await webImage(withTables(bytes, img.jpegTables), img.planar === 2 ? 1 : img.samples);
    else if (c === 50001) decoded = await webImage(bytes, img.planar === 2 ? 1 : img.samples);
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
