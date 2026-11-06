import assert from "node:assert/strict";
import test from "node:test";
import { gzipSync } from "node:zlib";
import { Archive, findEntry, parseDirectory, parseHeader, splitTileUrl, tileId } from "./pmtiles.mjs";

test("tileId numbers tiles along the Hilbert curve, zoom by zoom", () => {
  assert.deepEqual([tileId(0, 0, 0), tileId(1, 0, 0), tileId(1, 0, 1), tileId(1, 1, 1), tileId(1, 1, 0)], [0, 1, 2, 3, 4]);
  assert.equal(tileId(2, 1, 2), 12);
  assert.equal(tileId(14, 14552, 6451), 293554628);
  assert.throws(() => tileId(1, 2, 0), /outside its zoom level/);
  assert.throws(() => tileId(27, 0, 0), /zoom over 26/);
});

test("parseDirectory reads delta ids, runs, lengths and contiguous offsets; findEntry finds runs and leaves", () => {
  // Ids 5, 7 (a run of 3) and 20 (a leaf); offsets 0, then right after, then 100.
  const dir = new Uint8Array([3, 5, 2, 13, 1, 3, 0, 10, 20, 30, 1, 0, 101]);
  const entries = parseDirectory(dir);
  assert.deepEqual(entries, [
    { tileId: 5, offset: 0, length: 10, runLength: 1 },
    { tileId: 7, offset: 10, length: 20, runLength: 3 },
    { tileId: 20, offset: 100, length: 30, runLength: 0 },
  ]);
  assert.equal(findEntry(entries, 9).tileId, 7);
  assert.equal(findEntry(entries, 10), null);
  assert.equal(findEntry(entries, 50).tileId, 20);
  assert.equal(findEntry(entries, 4), null);
  assert.throws(() => parseDirectory(new Uint8Array([200, 1])), /entry count exceeds its size/);
  assert.throws(() => parseDirectory(new Uint8Array([1, 0xff, 0xff, 0xff])), /truncated/);
  assert.throws(() => parseDirectory(new Uint8Array(Array(12).fill(0xff))), /longer than 10 bytes/);
});

test("parseHeader refuses what is not a v3 archive", () => {
  assert.throws(() => parseHeader(new Uint8Array(10)), /too short/);
  assert.throws(() => parseHeader(new Uint8Array(127)), /not an archive/);
  const v2 = new Uint8Array(127);
  v2.set(new TextEncoder().encode("PMTiles"));
  v2[7] = 2;
  assert.throws(() => parseHeader(v2), /spec version 2/);
});

test("an Archive reads a tile through a gzip root directory; tiles outside its zooms are none", async () => {
  const tile = new TextEncoder().encode("tile 1/0/1");
  const root = gzipSync(Buffer.from([1, 2, 1, tile.length, 1]));
  const header = Buffer.alloc(127);
  header.write("PMTiles", 0, "ascii");
  header[7] = 3;
  const dataAt = 127 + root.length;
  [127, root.length, dataAt, 0, dataAt, 0, dataAt, tile.length].forEach((v, i) => header.writeBigUInt64LE(BigInt(v), 8 + i * 8));
  header[97] = 2;
  header[98] = 1;
  header[100] = 0;
  header[101] = 1;
  const bytes = Buffer.concat([header, root, tile]);
  const archive = new Archive("a", async (_, offset, length) => new Uint8Array(bytes.subarray(offset, offset + length)));
  assert.equal(new TextDecoder().decode(await archive.tile(1, 0, 1)), "tile 1/0/1");
  assert.equal(await archive.tile(1, 1, 1), null);
  assert.equal(await archive.tile(2, 0, 0), null);
});

test("splitTileUrl takes the archive and z/x/y of an http(s) pmtiles URL only", () => {
  assert.deepEqual(splitTileUrl("pmtiles://https://x.org/a.pmtiles/3/4/5"), { archive: "https://x.org/a.pmtiles", z: 3, x: 4, y: 5 });
  assert.equal(splitTileUrl("pmtiles://file:///a.pmtiles/3/4/5"), null);
  assert.equal(splitTileUrl("https://x.org/3/4/5.pbf"), null);
});

test("an Archive whose header fetch failed asks again", async () => {
  const header = Buffer.alloc(127);
  header.write("PMTiles", 0, "ascii");
  header[7] = 3;
  let fail = true;
  let fetches = 0;
  const archive = new Archive("a", async (_, offset, length) => {
    fetches++;
    if (fail) throw new Error("offline");
    return new Uint8Array(header.subarray(offset, offset + length));
  });
  await assert.rejects(archive.start(), /offline/);
  fail = false;
  assert.ok((await archive.start()).header);
  assert.equal(fetches, 2);
});

// An Archive whose every directory is one of three entries, with its fetches counted.
function directories(maxEntries) {
  const header = Buffer.alloc(127);
  header.write("PMTiles", 0, "ascii");
  header[7] = 3;
  header[97] = 1;
  const fetches = [];
  const archive = new Archive("a", async (_, offset, length) => {
    if (offset === 0) return new Uint8Array(header);
    fetches.push(offset);
    if (offset === 666) throw new Error("offline");
    return new Uint8Array([3, 5, 2, 13, 1, 3, 0, 10, 20, 30, 1, 0, 101]).subarray(0, length);
  }, maxEntries);
  return { archive, fetches };
}

test("an Archive drops its oldest directories past the limit in entries", async () => {
  const { archive, fetches } = directories(7);
  await archive.directory(1000, 13);
  await archive.directory(2000, 13);
  await archive.directory(1000, 13);
  assert.deepEqual([archive.directories.size, archive.entries, fetches.length], [2, 6, 2]);
  await archive.directory(3000, 13);
  assert.deepEqual([archive.directories.size, archive.entries], [2, 6]);
  await archive.directory(1000, 13);
  assert.deepEqual(fetches, [1000, 2000, 3000, 1000]);
});

test("an Archive keeps the newest directory even past the limit, and none that failed", async () => {
  const { archive } = directories(2);
  await archive.directory(1000, 13);
  await archive.directory(2000, 13);
  assert.deepEqual([[...archive.directories.keys()], archive.entries], [["2000:13"], 3]);
  await assert.rejects(archive.directory(666, 13), /offline/);
  assert.deepEqual([[...archive.directories.keys()], archive.entries], [["2000:13"], 3]);
});
