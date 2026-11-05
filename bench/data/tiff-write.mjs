// A TIFF writer for bench/data/geotiff-golden.mjs and the pack test: strips or tiles, planar 1 or
// 2, no compression, LZW, Deflate or PackBits, predictors 2 and 3, every sample format geotiff
// reads, BigTIFF, either byte order, several images (overviews), empty blocks and geo tags.
import { deflateSync } from "node:zlib";

/** TIFF 6.0 LZW (MSB first, early change), as libtiff writes it. */
export function lzwEncode(bytes) {
  const out = [];
  let acc = 0;
  let accBits = 0;
  let width = 9;
  const put = (code) => {
    acc = (acc << width) | code;
    accBits += width;
    while (accBits >= 8) {
      out.push((acc >>> (accBits - 8)) & 0xff);
      accBits -= 8;
    }
    acc &= (1 << accBits) - 1;
  };
  let dict = new Map();
  let next = 258;
  put(256);
  if (bytes.length === 0) {
    put(257);
    if (accBits > 0) out.push((acc << (8 - accBits)) & 0xff);
    return Uint8Array.from(out);
  }
  let w = bytes[0];
  for (let i = 1; i < bytes.length; i++) {
    const c = bytes[i];
    const key = w * 256 + c;
    const found = dict.get(key);
    if (found !== undefined) {
      w = found;
      continue;
    }
    put(w);
    dict.set(key, next++);
    if (next >= 1 << width && width < 12) width++;
    if (next >= 4094) {
      put(256);
      dict = new Map();
      next = 258;
      width = 9;
    }
    w = c;
  }
  put(w);
  next++;
  if (next >= 1 << width && width < 12) width++;
  put(257);
  if (accBits > 0) out.push((acc << (8 - accBits)) & 0xff);
  return Uint8Array.from(out);
}

/** PackBits (TIFF 6.0 §9). */
export function packbitsEncode(bytes) {
  const out = [];
  let i = 0;
  while (i < bytes.length) {
    let run = 1;
    while (i + run < bytes.length && run < 128 && bytes[i + run] === bytes[i]) run++;
    if (run >= 2) {
      out.push(257 - run, bytes[i]);
      i += run;
      continue;
    }
    let lit = 1;
    while (i + lit < bytes.length && lit < 128 && !(i + lit + 1 < bytes.length && bytes[i + lit] === bytes[i + lit + 1])) lit++;
    out.push(lit - 1, ...bytes.subarray(i, i + lit));
    i += lit;
  }
  return Uint8Array.from(out);
}

/** The IEEE half bits of `x` (rounded to nearest even), for values a half holds. */
function toHalf(x) {
  const f = new Float32Array([x]);
  const u = new Uint32Array(f.buffer)[0];
  const sign = (u >>> 16) & 0x8000;
  const e = ((u >>> 23) & 0xff) - 112;
  const m = u & 0x7fffff;
  if (((u >>> 23) & 0xff) === 0xff) return sign | 0x7c00 | (m ? 0x200 : 0);
  if (e >= 31) return sign | 0x7c00;
  if (e <= 0) {
    if (e < -10) return sign;
    const mm = (m | 0x800000) >> (1 - e);
    return sign | ((mm + 0x1000) >> 13);
  }
  return sign | ((e << 10) + ((m + 0x1000) >> 13));
}

/** The bytes of `value` as a sample of `format` and `bits`, in byte order `little`. */
function sampleBytes(value, format, bits, little) {
  const n = bits / 8;
  const b = new Uint8Array(n);
  const v = new DataView(b.buffer);
  if (format === 3) {
    if (bits === 16) v.setUint16(0, toHalf(value), little);
    else if (bits === 32) v.setFloat32(0, value, little);
    else v.setFloat64(0, value, little);
  } else if (bits === 8) v.setUint8(0, value & 0xff);
  else if (bits === 16) v.setUint16(0, value & 0xffff, little);
  else v.setUint32(0, value >>> 0, little);
  return b;
}

/**
 * One block's bytes before compression: `rows` rows of `width` pixels from (`x0`, `y0`) of
 * `values` (per sample, row-major, `w` x `h`), `samples` the samples it holds, padded with 0.
 */
function blockBytes(img, x0, y0, width, rows, samples, little) {
  const { bits, format, predictor = 1 } = img;
  const [w, h] = [img.width, img.height];
  const stride = samples.length;
  const out = [];
  for (let y = 0; y < rows; y++) {
    // The row's samples as integers (or floats), differenced for predictor 2.
    const row = [];
    for (let x = 0; x < width; x++) {
      for (const s of samples) {
        const [px, py] = [x0 + x, y0 + y];
        row.push(px < w && py < h ? img.values[s][py * w + px] : 0);
      }
    }
    if (predictor === 2) {
      const mod = 2 ** bits;
      for (let i = row.length - 1; i >= stride; i--) row[i] = (((row[i] - row[i - stride]) % mod) + mod) % mod;
    }
    if (bits % 8 !== 0) {
      // Packed, most significant bit first, the row ending on a byte.
      let acc = 0;
      let n = 0;
      for (const v of row) {
        for (let k = bits - 1; k >= 0; k--) {
          acc = (acc << 1) | ((v >> k) & 1);
          if (++n === 8) {
            out.push(acc);
            acc = 0;
            n = 0;
          }
        }
      }
      if (n > 0) out.push(acc << (8 - n));
      continue;
    }
    if (predictor === 3) {
      const bytes = bits / 8;
      const big = row.map((v) => sampleBytes(v, format, bits, false));
      const planes = new Uint8Array(row.length * bytes);
      for (let i = 0; i < row.length; i++) for (let b = 0; b < bytes; b++) planes[b * row.length + i] = big[i][b];
      for (let i = planes.length - 1; i >= stride; i--) planes[i] = (planes[i] - planes[i - stride]) & 0xff;
      out.push(...planes);
      continue;
    }
    for (const v of row) out.push(...sampleBytes(v, format, bits, little));
  }
  return Uint8Array.from(out);
}

function compress(bytes, c) {
  if (c === 5) return lzwEncode(bytes);
  if (c === 8) return new Uint8Array(deflateSync(bytes));
  if (c === 32773) return packbitsEncode(bytes);
  return bytes;
}

// A TIFF of `images` ({ width, height, values per sample, bits, format, planar, tile or rows, compression,
// predictor, photometric, subfile, geo, keys, nodata, empty blocks }), `little`-endian or not, BigTIFF if
// `big`, directories before the data if `ifdsFirst`.
export function tiffFile(images, { little = true, big = false, ifdsFirst = false } = {}) {
  const blocks = images.map((img) => {
    const spp = img.values.length;
    const [bw, bh] = img.tile ?? [img.width, Math.min(img.rows ?? img.height, img.height)];
    const across = Math.ceil(img.width / bw);
    const down = Math.ceil(img.height / bh);
    const list = [];
    for (const s of img.planar === 2 ? [...Array(spp).keys()] : [null]) {
      for (let by = 0; by < down; by++) {
        for (let bx = 0; bx < across; bx++) {
          const rows = img.tile ? bh : Math.min(bh, img.height - by * bh);
          const index = list.length;
          if (img.empty?.includes(index)) {
            list.push(new Uint8Array(0));
            continue;
          }
          const raw = blockBytes(img, bx * bw, by * bh, bw, rows, s === null ? [...Array(spp).keys()] : [s], little);
          list.push(compress(raw, img.compression ?? 1));
        }
      }
    }
    return { list, bw, bh };
  });
  const SHORT = 3;
  const LONG = big ? 16 : 4;
  const ifds = (dataStart) => {
    const parts = [];
    const offsets = [];
    let at = 0;
    for (let k = 0; k < images.length; k++) {
      const img = images[k];
      const { list, bw, bh } = blocks[k];
      const spp = img.values.length;
      const blockOffsets = [];
      let d = dataStart;
      for (const b of list) {
        blockOffsets.push(b.length === 0 ? 0 : d + blocks.slice(0, k).reduce((s, x) => s + x.list.reduce((t, y) => t + y.length, 0), 0));
        d += b.length;
      }
      const tags = [
        [256, LONG, [img.width]], [257, LONG, [img.height]], [258, SHORT, Array(spp).fill(img.bits)],
        [259, SHORT, [img.compression ?? 1]], [262, SHORT, [img.photometric ?? (spp >= 3 ? 2 : 1)]],
        [277, SHORT, [spp]], [284, SHORT, [img.planar ?? 1]], [339, SHORT, Array(spp).fill(img.format ?? 1)],
      ];
      if (img.subfile) tags.push([254, 4, [img.subfile]]);
      if (img.predictor && img.predictor !== 1) tags.push([317, SHORT, [img.predictor]]);
      if (img.tile) tags.push([322, SHORT, [bw]], [323, SHORT, [bh]], [324, LONG, blockOffsets], [325, LONG, list.map((b) => b.length)]);
      else tags.push([273, LONG, blockOffsets], [278, LONG, [bh]], [279, LONG, list.map((b) => b.length)]);
      if (img.geo?.pixelScale) tags.push([33550, 12, img.geo.pixelScale]);
      if (img.geo?.tiepoint) tags.push([33922, 12, img.geo.tiepoint]);
      if (img.geo?.transform) tags.push([34264, 12, img.geo.transform]);
      if (img.keys) tags.push([34735, SHORT, [1, 1, 0, img.keys.length, ...img.keys.flatMap(([key, v]) => [key, 0, 1, v])]]);
      if (img.nodata !== undefined) tags.push([42113, 2, [...new TextEncoder().encode(img.nodata + "\0")]]);
      tags.sort((a, b) => a[0] - b[0]);
      const size = { 2: 1, 3: 2, 4: 4, 12: 8, 16: 8 };
      const inline = big ? 8 : 4;
      const entry = big ? 20 : 12;
      const head = (big ? 8 : 2) + tags.length * entry + inline;
      const extra = tags.map(([, t, v]) => (v.length * size[t] > inline ? Math.ceil((v.length * size[t]) / 2) * 2 : 0));
      const total = head + extra.reduce((s, x) => s + x, 0);
      const b = new Uint8Array(total);
      const v = new DataView(b.buffer);
      const setN = (o, n, x) => {
        if (n === 1) v.setUint8(o, x);
        else if (n === 2) v.setUint16(o, x, little);
        else if (n === 4) v.setUint32(o, x, little);
        else v.setBigUint64(o, BigInt(x), little);
      };
      const ifdAt = (ifdsFirst ? (big ? 16 : 8) : dataStart + blocks.reduce((s, x) => s + x.list.reduce((t, y) => t + y.length, 0), 0)) + at;
      offsets.push(ifdAt);
      setN(0, big ? 8 : 2, tags.length);
      let ext = head;
      tags.forEach(([tag, t, vals], i) => {
        const e = (big ? 8 : 2) + i * entry;
        setN(e, 2, tag);
        setN(e + 2, 2, t);
        setN(e + 4, inline, vals.length);
        const n = vals.length * size[t];
        const put = (o) => vals.forEach((x, j) => (t === 12 ? v.setFloat64(o + j * 8, x, little) : setN(o + j * size[t], size[t], x)));
        if (n <= inline) put(e + 4 + inline);
        else {
          setN(e + 4 + inline, inline, ifdAt + ext);
          put(ext);
          ext += extra[i];
        }
      });
      parts.push({ b, nextAt: head - inline });
      at += total;
    }
    // Chain the directories.
    parts.forEach((p, i) => {
      const v = new DataView(p.b.buffer);
      const next = i + 1 < parts.length ? offsets[i + 1] : 0;
      if (big) v.setBigUint64(p.nextAt, BigInt(next), little);
      else v.setUint32(p.nextAt, next, little);
    });
    return { parts, first: offsets[0], size: at };
  };
  const header = big ? 16 : 8;
  const ifdSize = ifds(0).size;
  const dataStart = ifdsFirst ? header + ifdSize : header;
  const { parts, first } = ifds(dataStart);
  const data = blocks.flatMap((x) => x.list);
  const total = header + ifdSize + data.reduce((s, b) => s + b.length, 0);
  const out = new Uint8Array(total);
  const v = new DataView(out.buffer);
  out[0] = out[1] = little ? 0x49 : 0x4d;
  v.setUint16(2, big ? 43 : 42, little);
  if (big) {
    v.setUint16(4, 8, little);
    v.setBigUint64(8, BigInt(first), little);
  } else v.setUint32(4, first, little);
  let at = ifdsFirst ? header + ifdSize : header;
  for (const b of data) {
    out.set(b, at);
    at += b.length;
  }
  at = ifdsFirst ? header : at;
  for (const p of parts) {
    out.set(p.b, at);
    at += p.b.length;
  }
  return out;
}
