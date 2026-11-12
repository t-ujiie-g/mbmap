// Scene layer packages (I3S SLPK: a zip of a layer's resources, entries stored and mostly gzipped) read
// by HTTP range requests, from a Blob's slices or from memory. Esri's `@specialIndexFileHASH128@`
// (i3s-spec slpk_hashtable) finds entries without the central directory. Imports only zip.ts.
import { readCapped } from "../../../worker/js/body.mjs";
import { inflate } from "../zip.ts";

/** Most entries an archive or its hash table may list. */
export const MAX_SLPK_ENTRIES = 4_000_000;
/** Most bytes of a central directory read (a hash table has at most `MAX_SLPK_ENTRIES` rows). */
export const MAX_SLPK_DIRECTORY_BYTES = 256 << 20;
/** Most bytes an entry may hold, stored or inflated. */
export const MAX_SLPK_ENTRY_BYTES = 256 << 20;
/** Most bytes of a file read whole (a Response without ranges, or an ArrayBuffer). */
export const MAX_SLPK_BYTES = 1 << 30;

/** Bytes read from the end first: the end records, a zip comment, and most often the hash table's record. */
const TAIL_BYTES = 1 << 17;
/** Bytes read past a local header's name when its extra field is longer than the directory's. */
const HEAD_BYTES = 1 << 10;
/** Recent entries kept. */
const CACHED_ENTRIES = 32;
const HASH_NAME = "@specialIndexFileHASH128@";

/** Fetches `url` with `init` (a `Range` header); `fetch` without credentials by default. */
export type FetchRange = (url: string, init: RequestInit) => Promise<Response>;

/** An opened archive: `get` gives a resource by its REST path (`layer`, `nodepages/3`, `nodes/5/geometries/1`, …), gunzipped. */
export interface Slpk {
  readonly size: number;
  /** `"range"`: read by ranges (HTTP 206 or a Blob); `"whole"`: read once into memory. */
  readonly mode: "range" | "whole";
  /** `"hash"`: entries found by the hash table; `"directory"`: by the central directory. */
  readonly index: "hash" | "directory";
  get(path: string): Promise<Uint8Array | undefined>;
}

interface Source {
  size: number;
  mode: "range" | "whole";
  read(start: number, end: number): Promise<Uint8Array>;
}

/** `head`: the local header's least length (30 bytes and the name). */
interface Entry {
  name: string;
  head: number;
  method: number;
  compressed: number;
  at: number;
}

function fail(message: string): never {
  throw new Error(`SLPK: ${message}`);
}

const u64 = (v: DataView, at: number): number => {
  const n = v.getUint32(at, true) + v.getUint32(at + 4, true) * 2 ** 32;
  return n <= Number.MAX_SAFE_INTEGER ? n : fail("an offset or size past 2^53");
};
const view = (b: Uint8Array) => new DataView(b.buffer, b.byteOffset, b.byteLength);
const utf8 = new TextDecoder();

/** A Response's body, refused past `max` bytes. */
const body = (res: Response, max: number): Promise<Uint8Array> => readCapped(res, max, () => new Error(`SLPK: more than ${max} bytes`));

const memory = (bytes: Uint8Array): Source => ({ size: bytes.length, mode: "whole", read: async (s, e) => bytes.subarray(s, e) });

/** An HTTP source: the tail asked for by a suffix range; a 200 answer is the whole file, kept in memory. */
async function http(url: string, fetchRange: FetchRange): Promise<{ source: Source; tail?: Uint8Array }> {
  let res = await fetchRange(url, { headers: { Range: `bytes=-${TAIL_BYTES}` } });
  // Some servers refuse a suffix longer than the file (HTTP 416) instead of sending all of it.
  if (res.status === 416) res = await fetchRange(url, {});
  if (res.status === 200) return { source: memory(await body(res, MAX_SLPK_BYTES)) };
  if (res.status !== 206) fail(`${url}: HTTP ${res.status}`);
  const tail = await body(res, TAIL_BYTES);
  const m = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(res.headers.get("content-range") ?? "");
  let size = m ? Number(m[3]) : NaN;
  if (!m) {
    // A cross-origin server that does not expose Content-Range: its Content-Length says the size.
    const head = await fetchRange(url, { method: "HEAD" });
    size = Number(head.headers.get("content-length"));
  } else if (Number(m[2]) + 1 !== size || Number(m[2]) - Number(m[1]) + 1 !== tail.length) fail(`${url}: a range other than asked`);
  if (!Number.isSafeInteger(size) || size < tail.length) fail(`${url}: no size`);
  const inflight = new Map<string, Promise<Uint8Array>>();
  const read = (start: number, end: number): Promise<Uint8Array> => {
    const key = `${start}-${end}`;
    let p = inflight.get(key);
    if (!p) {
      p = fetchRange(url, { headers: { Range: `bytes=${start}-${end - 1}` } })
        .then(async (r) => {
          if (r.status !== 206) fail(`${url}: HTTP ${r.status} for a range`);
          const got = r.headers.get("content-range");
          if (got !== null && got !== `bytes ${start}-${end - 1}/${size}`) fail(`${url}: a range other than asked`);
          const b = await body(r, end - start);
          return b.length === end - start ? b : fail(`${url}: a short range`);
        })
        .finally(() => inflight.delete(key));
      inflight.set(key, p);
    }
    return p;
  };
  return { source: { size, mode: "range", read }, tail };
}

/** `source`'s reads, with the bytes from `from` on (the tail read first) served from memory. */
function withTail(source: Source, tail: Uint8Array, from: number): Source {
  const read = async (s: number, e: number): Promise<Uint8Array> => {
    if (s >= from) return tail.subarray(s - from, e - from);
    if (e <= from) return source.read(s, e);
    const out = new Uint8Array(e - s);
    out.set(await source.read(s, from));
    out.set(tail.subarray(0, e - from), from - s);
    return out;
  };
  return { ...source, read };
}

const K = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32));
const R = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];

/** The MD5 digest (RFC 1321) of `data`. */
export function md5(data: Uint8Array): Uint8Array {
  const n = data.length;
  const m = new Uint8Array((((n + 8) >>> 6) + 1) * 64);
  m.set(data);
  m[n] = 0x80;
  const v = view(m);
  v.setUint32(m.length - 8, (n * 8) >>> 0, true);
  v.setUint32(m.length - 4, Math.floor(n / 2 ** 29), true);
  const h = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476];
  for (let off = 0; off < m.length; off += 64) {
    let [a, b, c, d] = h;
    for (let i = 0; i < 64; i++) {
      const q = i >> 4;
      const f = q === 0 ? (b & c) | (~b & d) : q === 1 ? (d & b) | (~d & c) : q === 2 ? b ^ c ^ d : c ^ (b | ~d);
      const g = q === 0 ? i : q === 1 ? (5 * i + 1) & 15 : q === 2 ? (3 * i + 5) & 15 : (7 * i) & 15;
      const x = (a + f + K[i] + v.getUint32(off + g * 4, true)) | 0;
      const s = R[q * 4 + (i & 3)];
      [a, d, c] = [d, c, b];
      b = (b + ((x << s) | (x >>> (32 - s)))) | 0;
    }
    h[0] = (h[0] + a) | 0;
    h[1] = (h[1] + b) | 0;
    h[2] = (h[2] + c) | 0;
    h[3] = (h[3] + d) | 0;
  }
  const out = new Uint8Array(16);
  h.forEach((x, i) => view(out).setUint32(i * 4, x, true));
  return out;
}

/** The hash table's order: the key as two little-endian u64s. */
function compareKey(t: Uint8Array, at: number, key: Uint8Array): number {
  for (const half of [0, 8]) {
    for (let i = half + 7; i >= half; i--) if (t[at + i] !== key[i]) return t[at + i] - key[i];
  }
  return 0;
}

/** The end of central directory (zip64's when there is one): where the directory is, its size and count. */
async function endRecords(src: Source, tail: Uint8Array, from: number): Promise<{ at: number; size: number; count: number; end: number }> {
  const v = view(tail);
  let e = -1;
  for (let i = tail.length - 22; i >= Math.max(0, tail.length - 22 - 0xffff); i--) {
    if (v.getUint32(i, true) === 0x06054b50) {
      e = i;
      break;
    }
  }
  if (e < 0) fail("not a zip archive");
  if (v.getUint16(e + 4, true) !== 0 || v.getUint16(e + 6, true) !== 0) fail("split archives are not supported");
  let count = v.getUint16(e + 10, true);
  let size = v.getUint32(e + 12, true);
  let at = v.getUint32(e + 16, true);
  let end = from + e;
  if (e >= 20 && v.getUint32(e - 20, true) === 0x07064b50) {
    const record = u64(v, e - 12);
    if (record + 56 > from + e - 20) fail("a zip64 end record past its locator");
    const r = view(await src.read(record, record + 56));
    if (r.byteLength !== 56 || r.getUint32(0, true) !== 0x06064b50) fail("a malformed zip64 end record");
    if (r.getUint32(16, true) !== 0 || r.getUint32(20, true) !== 0) fail("split archives are not supported");
    count = u64(r, 32);
    size = u64(r, 40);
    at = u64(r, 48);
    end = record;
  } else if (count === 0xffff || size === 0xffffffff || at === 0xffffffff) fail("a zip64 archive without its end record");
  if (count > MAX_SLPK_ENTRIES) fail(`more than ${MAX_SLPK_ENTRIES} entries`);
  if (size > MAX_SLPK_DIRECTORY_BYTES) fail(`a central directory over ${MAX_SLPK_DIRECTORY_BYTES} bytes`);
  if (at + size > end) fail("a central directory past its end record");
  return { at, size, count, end };
}

/** A central directory record at `p` of `d`: its entry and length, sizes and offset from its zip64 field when marked so. */
function record(d: DataView, p: number): { entry: Entry; length: number } {
  if (p + 46 > d.byteLength || d.getUint32(p, true) !== 0x02014b50) fail("a malformed central directory");
  const [names, extra, comment] = [28, 30, 32].map((o) => d.getUint16(p + o, true));
  const length = 46 + names + extra + comment;
  if (p + length > d.byteLength) fail("a malformed central directory");
  if (d.getUint16(p + 8, true) & 1) fail("encrypted entries are not supported");
  const name = utf8.decode(new Uint8Array(d.buffer, d.byteOffset + p + 46, names));
  let [size, compressed, at] = [d.getUint32(p + 24, true), d.getUint32(p + 20, true), d.getUint32(p + 42, true)];
  for (let x = p + 46 + names; x + 4 <= p + 46 + names + extra; ) {
    const [id, len] = [d.getUint16(x, true), d.getUint16(x + 2, true)];
    if (id === 1) {
      let y = x + 4;
      const next = () => (y + 8 <= x + 4 + len ? ((y += 8), u64(d, y - 8)) : fail(`${name}: a short zip64 field`));
      if (size === 0xffffffff) size = next();
      if (compressed === 0xffffffff) compressed = next();
      if (at === 0xffffffff) at = next();
    }
    x += 4 + len;
  }
  if (Math.max(size, compressed) > MAX_SLPK_ENTRY_BYTES) fail(`${name}: over ${MAX_SLPK_ENTRY_BYTES} bytes`);
  return { entry: { name, head: 30 + names, method: d.getUint16(p + 10, true), compressed, at }, length };
}

/** Entries by name (and by lowercase name) from the directory `dir`, each lying between the next one's start and the directory. */
function directory(dir: Uint8Array, count: number, start: number): Map<string, Entry> {
  const d = view(dir);
  const all: Entry[] = [];
  for (let i = 0, p = 0; i < count; i++) {
    const { entry, length } = record(d, p);
    all.push(entry);
    p += length;
  }
  const byOffset = [...all].sort((a, b) => a.at - b.at);
  byOffset.forEach((e, i) => {
    if (e.at + e.head + e.compressed > (byOffset[i + 1]?.at ?? start)) fail(`${e.name}: overlaps the next entry or the directory`);
  });
  const out = new Map<string, Entry>();
  for (const e of all) if (!e.name.endsWith("/")) out.set(e.name, e);
  for (const e of all) if (!out.has(e.name.toLowerCase())) out.set(e.name.toLowerCase(), e);
  return out;
}

/** The entries a REST path of an I3S layer may be stored as, most likely first (loaders.gl's SLPKArchive's, and PCSL's). */
export function slpkCandidates(path: string): string[] {
  const p = path.replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
  const add = (exts: string[]) => exts.map((x) => p + x);
  if (p === "" || p === "layer" || p === "layer.json") return ["3dSceneLayer.json.gz", "3dSceneLayer.json"];
  if (/^nodepages\/\d+$/.test(p) || /^statistics\/(f_\d+\/\d+|summary)$/.test(p)) return add([".json.gz", ".json"]);
  if (/^sublayers\/\d+$/.test(p)) return add(["/3dSceneLayer.json.gz"]);
  if (/^nodes\/(\d+|root)$/.test(p)) return add(["/3dNodeIndexDocument.json.gz"]);
  if (/^nodes\/\d+\/shared$/.test(p)) return add(["/sharedResource.json.gz"]);
  if (/^nodes\/\d+\/textures\/[^/]+$/.test(p)) return add([".jpg", ".png", ".bin.dds.gz", ".bin.dds", ".dds", ".ktx2", ".bin.ktx2", ".ktx", ".jpg.gz", ".png.gz"]);
  if (/^nodes\/\d+\/geometries\/\d+$/.test(p)) return add([".bin.gz", ".draco.gz", ".bin", ".bin.pccxyz"]);
  if (/^nodes\/\d+\/attributes\/[^/]+\/\d+$/.test(p)) return add([".bin.gz", ".bin", ".bin.pccrgb", ".bin.pccint", ".bin.pccclass"]);
  return [p, ...add([".json.gz", ".bin.gz", ".gz", ".json", ".bin"])];
}

/** Gunzips `bytes` when they are gzip data. */
const gunzip = (bytes: Uint8Array, name: string) => (bytes[0] === 0x1f && bytes[1] === 0x8b ? inflate(bytes, "gzip", MAX_SLPK_ENTRY_BYTES, name) : Promise.resolve(bytes));

/**
 * Opens the scene layer package `source`: a URL read by range requests (or whole, when the server answers
 * 200), a Blob read by slices, or bytes. `fetchRange` makes every request.
 */
export async function openSlpk(source: string | Blob | ArrayBuffer | Uint8Array, fetchRange: FetchRange = (url, init) => fetch(url, { ...init, credentials: "omit" })): Promise<Slpk> {
  let src: Source;
  let tail: Uint8Array | undefined;
  if (typeof source === "string") ({ source: src, tail } = await http(source, fetchRange));
  else if (source instanceof Blob) src = { size: source.size, mode: "range", read: async (s, e) => new Uint8Array(await source.slice(s, e).arrayBuffer()) };
  else {
    const bytes = source instanceof Uint8Array ? source : new Uint8Array(source);
    if (bytes.length > MAX_SLPK_BYTES) fail(`more than ${MAX_SLPK_BYTES} bytes`);
    src = memory(bytes);
  }
  const from = src.size - (tail?.length ?? Math.min(src.size, TAIL_BYTES));
  tail ??= await src.read(from, src.size);
  src = withTail(src, tail, from);
  const cd = await endRecords(src, tail, from);
  const limit = cd.at;
  let entries: Map<string, Entry> | null = null;
  let hash: Uint8Array | null = null;
  // The hash table's offsets in order (its own entry's too): an entry ends where the next one starts.
  let starts: Float64Array | null = null;
  const readDirectory = async () => (entries ??= directory(await src.read(cd.at, cd.at + cd.size), cd.count, cd.at));
  if (cd.at < from) {
    // The hash table's record ends the directory: found in the tail, it saves reading the directory.
    const t = view(tail);
    const stop = cd.at + cd.size - from;
    for (let p = stop - 46 - HASH_NAME.length; p >= Math.max(0, cd.at - from); p--) {
      if (t.getUint32(p, true) !== 0x02014b50 || t.getUint16(p + 28, true) !== HASH_NAME.length) continue;
      const { entry, length } = record(t, p);
      if (entry.name !== HASH_NAME || p + length !== stop) continue;
      const rows = entry.compressed / 24;
      const table = Number.isInteger(rows) && rows <= MAX_SLPK_ENTRIES ? await entryBytes(entry) : null;
      if (table?.length === entry.compressed && sorted(table)) {
        hash = table;
        const tv = view(table);
        starts = new Float64Array(table.length / 24 + 1);
        for (let i = 0; i < table.length / 24; i++) starts[i] = u64(tv, i * 24 + 16);
        starts[starts.length - 1] = entry.at;
        starts.sort();
      }
      break;
    }
  }
  if (!hash) await readDirectory();

  /** The bytes of entry `e`, or of the one at offset `e` (the hash table's), which must be named `expect`. */
  async function entryBytes(e: Entry | number, expect?: string): Promise<Uint8Array> {
    const at = typeof e === "number" ? e : e.at;
    // Local extra fields are seldom longer than the directory's; an entry found by the hash table ends where the next starts.
    const guess = typeof e === "number" ? nextStart(e) : e.at + e.head + 64 + e.compressed;
    if (at + 30 > limit) fail("an entry past the directory");
    let head = await src.read(at, Math.min(limit, guess));
    const h = view(head);
    if (head.length < 30 || h.getUint32(0, true) !== 0x04034b50) fail("a malformed local header");
    const [flags, method, names, extra] = [h.getUint16(6, true), h.getUint16(8, true), h.getUint16(26, true), h.getUint16(28, true)];
    if (flags & 1) fail("encrypted entries are not supported");
    if (30 + names + extra > head.length) head = await src.read(at, Math.min(limit, at + 30 + names + extra + HEAD_BYTES));
    const lv = view(head);
    if (30 + names + extra > head.length) fail("a local header past the directory");
    const name = utf8.decode(head.subarray(30, 30 + names));
    let compressed: number;
    let size: number;
    if (typeof e === "number") {
      if (name.toLowerCase() !== expect!.toLowerCase()) fail(`${expect}: a local header of another name`);
      if (flags & 8) return entryBytes((await readDirectory()).get(name) ?? fail(`${name}: not in the directory`));
      [compressed, size] = [lv.getUint32(18, true), lv.getUint32(22, true)];
      for (let x = 30 + names; x + 4 <= 30 + names + extra; x += 4 + lv.getUint16(x + 2, true)) {
        if (lv.getUint16(x, true) === 1 && lv.getUint16(x + 2, true) >= 16) [size, compressed] = [size === 0xffffffff ? u64(lv, x + 4) : size, compressed === 0xffffffff ? u64(lv, x + 12) : compressed];
      }
    } else {
      if (name !== e.name) fail(`${e.name}: a local header of another name`);
      [compressed, size] = [e.compressed, 0];
    }
    if (Math.max(compressed, size) > MAX_SLPK_ENTRY_BYTES) fail(`${name}: over ${MAX_SLPK_ENTRY_BYTES} bytes`);
    const start = at + 30 + names + extra;
    if (start + compressed > limit) fail(`${name}: data past the directory`);
    const raw = start + compressed <= at + head.length ? head.subarray(start - at, start - at + compressed) : await src.read(start, start + compressed);
    if (method === 0) return raw.slice();
    if (method === 8) return inflate(raw, "deflate-raw", MAX_SLPK_ENTRY_BYTES, name);
    return fail(`${name}: compression method ${method} is not supported`);
  }

  /** Where the entry after the one at `at` starts, else the directory. */
  function nextStart(at: number): number {
    let [lo, hi] = [0, starts!.length];
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (starts![mid] <= at) lo = mid + 1;
      else hi = mid;
    }
    return lo < starts!.length ? Math.min(starts![lo], limit) : limit;
  }

  /** The local header offset the hash table gives `name`. */
  function hashed(name: string): number | undefined {
    const key = md5(new TextEncoder().encode(name));
    let [lo, hi] = [0, hash!.length / 24 - 1];
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const c = compareKey(hash!, mid * 24, key);
      if (c === 0) return u64(view(hash!), mid * 24 + 16);
      if (c < 0) lo = mid + 1;
      else hi = mid - 1;
    }
    return undefined;
  }

  async function lookup(name: string): Promise<Uint8Array | undefined> {
    for (const n of new Set([name.toLowerCase(), name])) {
      if (entries) {
        const e = entries.get(n);
        if (e) return entryBytes(e);
      } else {
        const at = hashed(n);
        if (at !== undefined) return entryBytes(at, n);
      }
    }
    return undefined;
  }

  const cache = new Map<string, Promise<Uint8Array | undefined>>();
  async function get(path: string): Promise<Uint8Array | undefined> {
    let p = cache.get(path);
    if (p) cache.delete(path);
    else
      p = (async () => {
        for (const name of slpkCandidates(path)) {
          const raw = await lookup(name);
          if (raw) return gunzip(raw, name);
        }
        return undefined;
      })();
    cache.set(path, p);
    if (cache.size > CACHED_ENTRIES) cache.delete(cache.keys().next().value!);
    p.catch(() => cache.get(path) === p && cache.delete(path));
    return p;
  }
  return { size: src.size, mode: src.mode, index: hash ? "hash" : "directory", get };
}

/** Whether the hash table's keys ascend, as binary search needs. */
function sorted(table: Uint8Array): boolean {
  for (let at = 24; at < table.length; at += 24) if (compareKey(table, at, table.subarray(at - 24, at - 8)) <= 0) return false;
  return true;
}

/** Where `slpkResources` puts an archive's resources: a layer read at this URL asks for them under it. */
export const SLPK_URL = "slpk://archive/";

/** An archive's resources by REST path or by URL under `SLPK_URL` (its query left out): parsed JSON or bytes; a missing one throws. */
export function slpkResources(slpk: Slpk): { url: string; json(path: string): Promise<any>; bytes(path: string): Promise<Uint8Array> } {
  const bytes = async (path: string) => {
    const rest = path.startsWith(SLPK_URL.slice(0, -1)) ? path.slice(SLPK_URL.length - 1).replace(/[?#].*$/, "") : path;
    return (await slpk.get(rest)) ?? fail(`no ${rest || "layer"} in the archive`);
  };
  return { url: SLPK_URL, bytes, json: async (path) => JSON.parse(utf8.decode(await bytes(path))) };
}
