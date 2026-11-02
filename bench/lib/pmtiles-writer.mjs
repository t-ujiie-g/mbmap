// PMTiles v3 archives for tests (bench/pmtiles/golden.mjs, the pack test),
// written as the spec lays them out: header, root directory, metadata, leaf
// directories, tile data; directories gzip-compressed.
import { gzipSync } from "node:zlib";
import { tileId } from "../../worker/js/pmtiles.mjs";

const varint = (out, v) => {
  for (; v >= 0x80; v = Math.floor(v / 128)) out.push((v % 128) | 0x80);
  out.push(v);
};

function directory(entries) {
  const out = [];
  varint(out, entries.length);
  let last = 0;
  for (const e of entries) {
    varint(out, e.tileId - last);
    last = e.tileId;
  }
  for (const e of entries) varint(out, e.runLength);
  for (const e of entries) varint(out, e.length);
  entries.forEach((e, i) => varint(out, i > 0 && e.offset === entries[i - 1].offset + entries[i - 1].length ? 0 : e.offset + 1));
  return gzipSync(Buffer.from(out));
}

/** A PMTiles v3 archive of `tiles` ({z, x, y, bytes}); `leafSize` entries per leaf directory, or none. */
export function writeArchive(tiles, { tileType, gzipTiles = false, leafSize = 0 }) {
  const sorted = tiles.map((t) => ({ ...t, id: tileId(t.z, t.x, t.y) })).sort((a, b) => a.id - b.id);
  const data = [];
  let at = 0;
  const entries = sorted.map((t) => {
    const bytes = gzipTiles ? gzipSync(t.bytes) : t.bytes;
    data.push(bytes);
    const e = { tileId: t.id, offset: at, length: bytes.length, runLength: 1 };
    at += bytes.length;
    return e;
  });
  let root;
  let leaves = Buffer.alloc(0);
  if (leafSize > 0) {
    const parts = [];
    const rootEntries = [];
    let leafAt = 0;
    for (let i = 0; i < entries.length; i += leafSize) {
      const leaf = directory(entries.slice(i, i + leafSize));
      rootEntries.push({ tileId: entries[i].tileId, offset: leafAt, length: leaf.length, runLength: 0 });
      parts.push(leaf);
      leafAt += leaf.length;
    }
    root = directory(rootEntries);
    leaves = Buffer.concat(parts);
  } else {
    root = directory(entries);
  }
  const meta = Buffer.from("{}");
  const header = Buffer.alloc(127);
  const lon = (x, z) => (x / 2 ** z) * 360 - 180;
  const lat = (y, z) => (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / 2 ** z))) * 180) / Math.PI;
  const z = tiles[0].z;
  const xs = tiles.map((t) => t.x);
  const ys = tiles.map((t) => t.y);
  const offsets = [127, root.length, 127 + root.length, meta.length, 127 + root.length + meta.length, leaves.length,
    127 + root.length + meta.length + leaves.length, at, tiles.length, tiles.length, tiles.length];
  header.write("PMTiles", 0, "ascii");
  header.writeUInt8(3, 7);
  offsets.forEach((v, i) => header.writeBigUInt64LE(BigInt(v), 8 + i * 8));
  header.writeUInt8(1, 96);
  header.writeUInt8(2, 97);
  header.writeUInt8(gzipTiles ? 2 : 1, 98);
  header.writeUInt8(tileType, 99);
  header.writeUInt8(z, 100);
  header.writeUInt8(z, 101);
  const e7 = (v) => Math.round(v * 1e7);
  header.writeInt32LE(e7(lon(Math.min(...xs), z)), 102);
  header.writeInt32LE(e7(lat(Math.max(...ys) + 1, z)), 106);
  header.writeInt32LE(e7(lon(Math.max(...xs) + 1, z)), 110);
  header.writeInt32LE(e7(lat(Math.min(...ys), z)), 114);
  header.writeUInt8(z, 118);
  return Buffer.concat([header, root, meta, leaves, ...data]);
}

