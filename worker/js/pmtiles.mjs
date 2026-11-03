// PMTiles v3 archives over HTTP range requests, as pmtiles 4.5.0 reads them
// (src/index.ts; BSD-3-Clause, Copyright (c) 2021 Protomaps LLC; see NOTICE).
// Archives are untrusted: sizes, entry counts and nesting are capped.

import { readCapped } from "./body.mjs";

/** Bytes fetched first: the 127-byte header and, in most archives, the root directory. */
export const FIRST_BYTES = 16384;
/** Largest directory or tile read, before and after decompression. */
export const MAX_PART_BYTES = 32 * 1024 * 1024;
const MAX_LEAF_DEPTH = 3;
const MAX_DIRECTORIES = 64;

/** Tile types of the header: what `tileType` holds. */
export const TILE_TYPES = ["unknown", "mvt", "png", "jpeg", "webp", "avif"];

function uint64(v, at) {
  return v.getUint32(at + 4, true) * 2 ** 32 + v.getUint32(at, true);
}

/** The header of an archive (its first 127 bytes or more), as pmtiles' `bytesToHeader`. */
export function parseHeader(bytes) {
  if (bytes.length < 127) throw new Error("PMTiles: header too short");
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (String.fromCharCode(...bytes.subarray(0, 7)) !== "PMTiles") throw new Error("PMTiles: not an archive");
  const specVersion = v.getUint8(7);
  if (specVersion !== 3) throw new Error(`PMTiles: spec version ${specVersion} is not supported`);
  const int = (at) => v.getInt32(at, true) / 1e7;
  return {
    rootDirectoryOffset: uint64(v, 8),
    rootDirectoryLength: uint64(v, 16),
    leafDirectoryOffset: uint64(v, 40),
    tileDataOffset: uint64(v, 56),
    internalCompression: v.getUint8(97),
    tileCompression: v.getUint8(98),
    tileType: v.getUint8(99),
    minZoom: v.getUint8(100),
    maxZoom: v.getUint8(101),
    bounds: [int(102), int(106), int(110), int(114)],
    center: [int(119), int(123), v.getUint8(118)],
  };
}

function readVarint(p) {
  let value = 0;
  for (let shift = 0; shift < 70; shift += 7) {
    if (p.pos >= p.buf.length) throw new Error("PMTiles: truncated directory");
    const b = p.buf[p.pos++];
    value += (b & 0x7f) * 2 ** shift;
    if (b < 0x80) return value;
  }
  throw new Error("PMTiles: varint longer than 10 bytes");
}

/** A directory's entries (`tileId`, `offset`, `length`, `runLength`), as pmtiles' `deserializeIndex`. */
export function parseDirectory(bytes) {
  const p = { buf: bytes, pos: 0 };
  const n = readVarint(p);
  // Each entry takes at least four bytes.
  if (n > bytes.length / 4) throw new Error("PMTiles: directory entry count exceeds its size");
  const entries = [];
  let last = 0;
  for (let i = 0; i < n; i++) {
    last += readVarint(p);
    entries.push({ tileId: last, offset: 0, length: 0, runLength: 1 });
  }
  for (const e of entries) e.runLength = readVarint(p);
  for (const e of entries) e.length = readVarint(p);
  entries.forEach((e, i) => {
    const v = readVarint(p);
    e.offset = v === 0 && i > 0 ? entries[i - 1].offset + entries[i - 1].length : v - 1;
  });
  return entries;
}

/** Tile z/x/y's Hilbert id (pmtiles' `zxyToTileId`). */
export function tileId(z, x, y) {
  if (z > 26) throw new Error("PMTiles: zoom over 26");
  if (x < 0 || y < 0 || x >= 2 ** z || y >= 2 ** z) throw new Error("PMTiles: tile outside its zoom level");
  let acc = (4 ** z - 1) / 3;
  let [tx, ty] = [x, y];
  for (let s = 2 ** (z - 1); s >= 1; s /= 2) {
    const rx = (tx & s) > 0 ? 1 : 0;
    const ry = (ty & s) > 0 ? 1 : 0;
    acc += ((3 * rx) ^ ry) * s * s;
    if (ry === 0) {
      if (rx === 1) [tx, ty] = [s - 1 - ty, s - 1 - tx];
      else [tx, ty] = [ty, tx];
    }
  }
  return acc;
}

/** The entry holding tile `id` or the leaf directory over it (pmtiles' `findTile`). */
export function findEntry(entries, id) {
  let m = 0;
  let n = entries.length - 1;
  while (m <= n) {
    const k = (n + m) >> 1;
    const cmp = id - entries[k].tileId;
    if (cmp > 0) m = k + 1;
    else if (cmp < 0) n = k - 1;
    else return entries[k];
  }
  if (n >= 0 && (entries[n].runLength === 0 || id - entries[n].tileId < entries[n].runLength)) return entries[n];
  return null;
}

async function decompress(bytes, compression) {
  if (compression === 0 || compression === 1) return bytes;
  if (compression !== 2) throw new Error(`PMTiles: compression ${compression} is not supported (only none and gzip)`);
  const reader = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip")).getReader();
  const parts = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > MAX_PART_BYTES) {
      reader.cancel();
      throw new Error("PMTiles: part too large once decompressed");
    }
    parts.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.length;
  }
  return out;
}

/**
 * One archive at `url`, read through `fetchRange(url, offset, length)` (a Promise of the bytes):
 * its header and directories are cached, tiles fetched as asked.
 */
export class Archive {
  constructor(url, fetchRange) {
    this.url = url;
    this.fetchRange = fetchRange;
    this.first = null;
    this.directories = new Map();
  }

  /** The header, and the first bytes it came with. */
  start() {
    this.first ??= this.fetchRange(this.url, 0, FIRST_BYTES).then((bytes) => ({ bytes, header: parseHeader(bytes) }));
    return this.first;
  }

  async directory(offset, length) {
    const key = `${offset}:${length}`;
    let dir = this.directories.get(key);
    if (!dir) {
      if (length > MAX_PART_BYTES) throw new Error("PMTiles: directory too large");
      const { bytes, header } = await this.start();
      dir = (async () => {
        const raw = offset + length <= bytes.length ? bytes.subarray(offset, offset + length) : await this.fetchRange(this.url, offset, length);
        return parseDirectory(await decompress(raw, header.internalCompression));
      })();
      if (this.directories.size >= MAX_DIRECTORIES) this.directories.delete(this.directories.keys().next().value);
      this.directories.set(key, dir);
    }
    return dir;
  }

  /** Tile z/x/y's bytes, decompressed; null where the archive has none. */
  async tile(z, x, y) {
    const { header } = await this.start();
    if (z < header.minZoom || z > header.maxZoom) return null;
    const id = tileId(z, x, y);
    let offset = header.rootDirectoryOffset;
    let length = header.rootDirectoryLength;
    for (let depth = 0; depth <= MAX_LEAF_DEPTH; depth++) {
      const entry = findEntry(await this.directory(offset, length), id);
      if (!entry) return null;
      if (entry.runLength > 0) {
        if (entry.length > MAX_PART_BYTES) throw new Error("PMTiles: tile too large");
        const raw = await this.fetchRange(this.url, header.tileDataOffset + entry.offset, entry.length);
        return decompress(raw, header.tileCompression);
      }
      offset = header.leafDirectoryOffset + entry.offset;
      length = entry.length;
    }
    throw new Error("PMTiles: leaf directories nested too deep");
  }
}

/** Splits `pmtiles://<archive URL>/{z}/{x}/{y}` (as the map asks for tiles); null for other URLs. */
export function splitTileUrl(url) {
  const m = /^pmtiles:\/\/(https?:\/\/.+)\/(\d+)\/(\d+)\/(\d+)$/.exec(url);
  return m ? { archive: m[1], z: Number(m[2]), x: Number(m[3]), y: Number(m[4]) } : null;
}

/** A range of `url` without credentials; a server that ignores Range is refused rather than read whole. */
export async function fetchRange(url, offset, length, signal) {
  const res = await fetch(url, { headers: { Range: `bytes=${offset}-${offset + length - 1}` }, credentials: "omit", signal });
  if (res.status !== 206 && !(res.status === 200 && offset === 0 && Number(res.headers.get("content-length")) <= length)) {
    throw new Error(`PMTiles: ${url} answered ${res.status} to a range request`);
  }
  return readCapped(res, length);
}
