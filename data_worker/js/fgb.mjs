// FlatGeobuf's header fields, packed R-tree search and HTTP range reads, as flatgeobuf 4.6.1
// reads them (packedrtree.js, http-reader.js; BSD License, Copyright (c) 2018 Björn Harrtell;
// see NOTICE); data.wasm reads the features. Import-free.

const MAX_HEADER_BYTES = 10 * 1024 * 1024;
const NODE_BYTES = 40;
// flatgeobuf's extraRequestThreshold: ranges this close are read in one request.
const GAP_BYTES = 256 * 1024;
// What flatgeobuf's HttpReader reads first: 2024 bytes of header and three levels of 16 nodes.
const FIRST_BYTES = 2024 + (1 + 16 + 256) * NODE_BYTES;
const PARALLEL = 6;

function fail(message) {
  throw new Error(`malformed FlatGeobuf: ${message}`);
}

/** The header's length (after the magic bytes and its u32 size), or an error for a file that is not one. */
export function headerLength(bytes) {
  if (bytes.length < 12 || bytes[0] !== 0x66 || bytes[1] !== 0x67 || bytes[2] !== 0x62) fail("not a FlatGeobuf file");
  const n = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(8, true);
  if (n < 8 || n > MAX_HEADER_BYTES) fail("invalid header size");
  return n;
}

/**
 * The fields of the header in `bytes` (from the start of the file, header included) that the
 * search and the CRS need: `count`, `nodeSize` (0 without an index) and `crs` (`{ org, code, wkt }` or null).
 */
export function readHeader(bytes) {
  const length = headerLength(bytes);
  if (bytes.length < 12 + length) fail("header past the end of the data");
  const v = new DataView(bytes.buffer, bytes.byteOffset + 8, 4 + length);
  const decoder = new TextDecoder();
  const u32 = (at) => v.getUint32(at, true);
  const field = (table, i) => {
    const vt = table - v.getInt32(table, true);
    const slot = 4 + i * 2;
    const off = slot + 2 > v.getUint16(vt, true) ? 0 : v.getUint16(vt + slot, true);
    return off === 0 ? -1 : table + off;
  };
  const table = (t, i) => {
    const at = field(t, i);
    return at < 0 ? -1 : at + u32(at);
  };
  const string = (t, i) => {
    const at = table(t, i);
    return at < 0 ? null : decoder.decode(new Uint8Array(v.buffer, v.byteOffset + at + 4, u32(at)));
  };
  try {
    const header = 4 + u32(4);
    const countAt = field(header, 8);
    const sizeAt = field(header, 9);
    const crsAt = table(header, 10);
    const codeAt = crsAt < 0 ? -1 : field(crsAt, 1);
    return {
      length,
      count: countAt < 0 ? 0 : Number(v.getBigUint64(countAt, true)),
      nodeSize: sizeAt < 0 ? 16 : v.getUint16(sizeAt, true),
      crs: crsAt < 0 ? null : { org: string(crsAt, 0), code: codeAt < 0 ? 0 : v.getInt32(codeAt, true), wkt: string(crsAt, 4) },
    };
  } catch (e) {
    if (e instanceof RangeError) fail("header past the end of the data");
    throw e;
  }
}

/** The CRS a header names: an EPSG code, else its WKT, else undefined (EPSG:4326). */
export function headerCrs(crs) {
  if (!crs) return undefined;
  if ((crs.org === null || /^epsg$/i.test(crs.org)) && crs.code > 0) return crs.code;
  return crs.wkt?.trim() ? { wkt: crs.wkt } : undefined;
}

/** A header's node size as flatgeobuf's `calcTreeSize` clamps it: one under 2 would never shrink a level. */
const clampNodeSize = (nodeSize) => Math.min(Math.max(nodeSize, 2), 65535);

/** Each level's node range in a packed R-tree of `count` items, leaves first (flatgeobuf's `generateLevelBounds`). */
export function levelBounds(count, nodeSize) {
  const perNode = clampNodeSize(nodeSize);
  let n = count;
  let nodes = n;
  const sizes = [n];
  do {
    n = Math.ceil(n / perNode);
    nodes += n;
    sizes.push(n);
  } while (n > 1);
  const bounds = [];
  for (const size of sizes) {
    bounds.push([nodes - size, nodes]);
    nodes -= size;
  }
  return bounds;
}

/** Bytes of a packed R-tree (flatgeobuf's `calcTreeSize`). */
export function treeBytes(count, nodeSize) {
  return levelBounds(count, nodeSize)[0][1] * NODE_BYTES;
}

/**
 * The features whose boxes meet `[minX, minY, maxX, maxY]`, as flatgeobuf's `streamSearch` walks the
 * tree: `[offset, index, length]` each (length null for the file's last), nodes read through
 * `readNode(offset, length)` (a Promise of bytes, offsets into the tree).
 */
export async function search(count, nodeSize, [minX, minY, maxX, maxY], readNode) {
  const perNode = clampNodeSize(nodeSize);
  const bounds = levelBounds(count, perNode);
  const firstLeaf = bounds[0][0];
  const queue = [{ nodes: [0, 1], level: bounds.length - 1 }];
  const found = [];
  // A tree that points back up or at nodes twice would be walked without end.
  let budget = 2 * bounds[0][1] + 65536;
  for (let head = 0; head < queue.length; head++) {
    const range = queue[head];
    const start = range.nodes[0];
    const leaf = start >= firstLeaf;
    if (range.level < 0 || (range.level === 0) !== leaf) fail("a node at the wrong level");
    const [, levelEnd] = bounds[range.level];
    const end = Math.min(range.nodes[1] + perNode, levelEnd);
    const readEnd = leaf && end < levelEnd ? end + 1 : end;
    budget -= readEnd - start;
    if (budget < 0 || found.length > count) fail("an index that does not form a tree");
    const bytes = await readNode(start * NODE_BYTES, (readEnd - start) * NODE_BYTES);
    if (bytes.length < (readEnd - start) * NODE_BYTES) fail("index past the end of the data");
    const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    for (let i = start; i < end; i++) {
      const at = (i - start) * NODE_BYTES;
      if (maxX < v.getFloat64(at, true) || maxY < v.getFloat64(at + 8, true) || minX > v.getFloat64(at + 16, true) || minY > v.getFloat64(at + 24, true)) continue;
      const offset = Number(v.getBigUint64(at + 32, true));
      if (!Number.isSafeInteger(offset)) fail("an offset past the end of the data");
      if (leaf) {
        const length = i < bounds[0][1] - 1 ? Number(v.getBigUint64(at + NODE_BYTES + 32, true)) - offset : null;
        found.push([offset, i - firstLeaf, length]);
        continue;
      }
      if (offset >= bounds[0][1]) fail("a node past the end of the index");
      const near = queue.length > head + 1 ? queue[queue.length - 1] : undefined;
      if (near?.level === range.level - 1 && offset < near.nodes[1] + GAP_BYTES / NODE_BYTES) {
        if (offset > near.nodes[1]) near.nodes[1] = offset;
        continue;
      }
      queue.push({ nodes: [offset, offset], level: range.level - 1 });
    }
    queue[head] = undefined;
  }
  return found;
}

/** `bbox` as a search rectangle, or an error. */
function rect(bbox) {
  if (!Array.isArray(bbox) || bbox.length !== 4 || !bbox.every(Number.isFinite) || bbox[0] > bbox[2] || bbox[1] > bbox[3]) {
    throw new Error("invalid bbox");
  }
  return bbox;
}

/**
 * The header of `bytes` and the features `found` in `bytes` (at `featuresAt`), as data.wasm's
 * `read_flatgeobuf` takes them with ids, at most `max` bytes: leaves may all name one large feature.
 */
function pack(header, found, featureAt, max) {
  const parts = [header];
  const ids = new Uint32Array(found.length);
  let total = header.length + ids.length * 4;
  found.forEach((f, i) => {
    const bytes = featureAt(f);
    parts.push(bytes);
    total += bytes.length;
    if (total > max) throw new Error(`data larger than ${max} bytes`);
    ids[i] = f[1];
  });
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  out.set(new Uint8Array(ids.buffer), at);
  return { bytes: out, ids: ids.length };
}

/** A size-prefixed feature at `at` of `bytes`. */
function featureIn(bytes, at) {
  if (at < 0 || at + 4 > bytes.length) fail("feature past the end of the data");
  const n = new DataView(bytes.buffer, bytes.byteOffset + at, 4).getUint32(0, true);
  if (at + 4 + n > bytes.length) fail("feature past the end of the data");
  return bytes.subarray(at, at + 4 + n);
}

/**
 * The features of the FlatGeobuf `bytes` in `bbox`, as `{ bytes, ids }` for `read_flatgeobuf`
 * (bytes: its header, the features, then `ids` u32 indices), at most `max` bytes.
 */
export async function selectBytes(bytes, bbox, max) {
  const header = readHeader(bytes);
  if (header.nodeSize === 0) throw new Error("the FlatGeobuf has no index to read a bbox with");
  if (header.count === 0) return pack(bytes.subarray(0, 12 + header.length), [], null, max);
  const tree = 12 + header.length;
  const features = tree + treeBytes(header.count, header.nodeSize);
  const found = await search(header.count, header.nodeSize, rect(bbox), async (o, n) => bytes.subarray(tree + o, tree + o + n));
  return pack(bytes.subarray(0, tree), found, ([offset]) => featureIn(bytes, features + offset), max);
}

/**
 * A range of `url` through `http` (worker/js/body.mjs's `fetchInit`, which takes `init`, and
 * `readCapped`); `{ whole }` if the server sent all of it.
 */
async function fetchRange({ fetchInit, readCapped }, url, init, offset, length, max) {
  const options = fetchInit(init);
  options.headers = { ...options.headers, Range: `bytes=${offset}-${offset + length - 1}` };
  const res = await fetch(url, options);
  if (res.status === 200) return { whole: await readCapped(res, max) };
  if (res.status !== 206) throw new Error(`HTTP ${res.status} for ${url}`);
  const start = /^bytes (\d+)-/.exec(res.headers.get("content-range") ?? "");
  if (!start || Number(start[1]) !== offset) throw new Error(`${url} answered another range`);
  const bytes = await readCapped(res, length);
  return { bytes };
}

/**
 * The features of the FlatGeobuf at `url` in `bbox`, read with range requests (`http` as
 * `fetchRange` takes it) as flatgeobuf's HttpReader reads them (header, index levels, then features
 * in batches), at most `max` bytes in all; a server that answers with the whole file has it read from those bytes.
 */
export async function selectUrl(url, init, bbox, max, http) {
  rect(bbox);
  let fetched = 0;
  const get = async (offset, length) => {
    fetched += length;
    if (fetched > max) throw new Error(`data larger than ${max} bytes`);
    return fetchRange(http, url, init, offset, length, max);
  };
  const first = await get(0, FIRST_BYTES);
  if (first.whole) return selectBytes(first.whole, bbox, max);
  let start = first.bytes;
  const length = headerLength(start);
  if (start.length < 12 + length) {
    const more = await get(0, 12 + length + (1 + 16 + 256) * NODE_BYTES);
    if (more.whole) return selectBytes(more.whole, bbox, max);
    start = more.bytes;
  }
  const header = readHeader(start);
  if (header.nodeSize === 0) throw new Error("the FlatGeobuf has no index to read a bbox with");
  const tree = 12 + header.length;
  if (header.count === 0) return pack(start.subarray(0, tree), [], null, max);
  const features = tree + treeBytes(header.count, header.nodeSize);
  const found = await search(header.count, header.nodeSize, rect(bbox), async (o, n) => {
    if (tree + o + n <= start.length) return start.subarray(tree + o, tree + o + n);
    const r = await get(tree + o, n);
    if (r.whole) throw new Error(`${url} stopped answering range requests`);
    return r.bytes;
  });
  // Batches of features no more than GAP_BYTES apart, each read in one request.
  const batches = [];
  for (const f of found) {
    const last = batches.at(-1)?.at(-1);
    if (!last || f[0] - (last[0] + (last[2] ?? 4)) > GAP_BYTES) batches.push([f]);
    else batches.at(-1).push(f);
  }
  const read = new Map();
  for (let i = 0; i < batches.length; i += PARALLEL) {
    await Promise.all(batches.slice(i, i + PARALLEL).map(async (batch) => {
      const from = batch[0][0];
      const [lastAt, , lastLength] = batch.at(-1);
      const r = await get(features + from, lastAt + (lastLength ?? 4) - from);
      if (r.whole) throw new Error(`${url} stopped answering range requests`);
      for (const f of batch) {
        const at = f[0] - from;
        if (at + 4 <= r.bytes.length) {
          const n = new DataView(r.bytes.buffer, r.bytes.byteOffset + at, 4).getUint32(0, true);
          if (at + 4 + n <= r.bytes.length) {
            read.set(f[1], r.bytes.subarray(at, at + 4 + n));
            continue;
          }
          const rest = await get(features + f[0], 4 + n);
          read.set(f[1], featureIn(rest.bytes ?? fail("feature past the end of the data"), 0));
        } else {
          fail("feature past the end of the data");
        }
      }
    }));
  }
  return pack(start.subarray(0, tree), found, (f) => read.get(f[1]), max);
}
