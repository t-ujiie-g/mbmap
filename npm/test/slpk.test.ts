import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { crc32, deflateRawSync, gzipSync } from "node:zlib";
import { md5, openSlpk, slpkCandidates, slpkResources, SLPK_URL, type FetchRange } from "../src/i3s/slpk.ts";

interface File {
  name: string;
  data: Uint8Array;
  method?: number;
}

interface Options {
  zip64?: boolean;
  hash?: boolean;
  /** Entries of 100 bytes added, so the directory falls outside the first read. */
  filler?: number;
  comment?: number;
}

const enc = (s: string) => new TextEncoder().encode(s);
const concat = (parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((s, p) => s + p.length, 0));
  parts.reduce((at, p) => (out.set(p, at), at + p.length), 0);
  return out;
};
const le = (bytes: number, value: number | bigint) => {
  const b = new Uint8Array(bytes);
  const v = new DataView(b.buffer);
  if (bytes === 2) v.setUint16(0, Number(value), true);
  else if (bytes === 4) v.setUint32(0, Number(value), true);
  else v.setBigUint64(0, BigInt(value), true);
  return b;
};

/** A zip of `files` as SLPK writers make it: stored unless `method` 8; with `zip64` every size and offset in zip64 fields; with `hash` Esri's hash table last. */
function slpk(files: File[], o: Options = {}): Uint8Array {
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  const offsets: [Uint8Array, number][] = [];
  let offset = 0;
  const write = (f: File) => {
    const method = f.method ?? 0;
    const data = method === 8 ? new Uint8Array(deflateRawSync(f.data)) : f.data;
    const name = enc(f.name);
    const big = o.zip64 === true;
    const extra = big ? concat([le(2, 1), le(2, 16), le(8, f.data.length), le(8, data.length)]) : new Uint8Array(0);
    const cextra = big ? concat([le(2, 1), le(2, 24), le(8, f.data.length), le(8, data.length), le(8, offset)]) : new Uint8Array(0);
    const sizes = big ? [le(4, 0xffffffff), le(4, 0xffffffff)] : [le(4, data.length), le(4, f.data.length)];
    const common = [le(2, 0), le(2, method), le(4, 0), le(4, crc32(f.data)), ...sizes, le(2, name.length)];
    parts.push(concat([le(4, 0x04034b50), le(2, 45), ...common, le(2, extra.length), name, extra, data]));
    central.push(concat([le(4, 0x02014b50), le(2, 45), le(2, 45), ...common, le(2, cextra.length), le(2, 0), le(2, 0), le(2, 0), le(4, 0), le(4, big ? 0xffffffff : offset), name, cextra]));
    offsets.push([name, offset]);
    offset += parts[parts.length - 1].length;
  };
  files.forEach(write);
  for (let i = 0; i < (o.filler ?? 0); i++) write({ name: `nodes/${i}/filler/padding-${i}.bin`, data: new Uint8Array(100) });
  if (o.hash) {
    const rows = offsets.map(([name, at]) => concat([md5(enc(new TextDecoder().decode(name).toLowerCase())), le(8, at)]));
    rows.sort((a, b) => {
      const [x, y] = [new DataView(a.buffer), new DataView(b.buffer)];
      const c = x.getBigUint64(0, true) - y.getBigUint64(0, true) || x.getBigUint64(8, true) - y.getBigUint64(8, true);
      return c < 0n ? -1 : c > 0n ? 1 : 0;
    });
    write({ name: "@specialIndexFileHASH128@", data: concat(rows) });
  }
  const dir = concat(central);
  const n = central.length;
  const tail: Uint8Array[] = [];
  if (o.zip64) {
    const record = offset + dir.length;
    tail.push(concat([le(4, 0x06064b50), le(8, 44), le(2, 45), le(2, 45), le(4, 0), le(4, 0), le(8, n), le(8, n), le(8, dir.length), le(8, offset)]));
    tail.push(concat([le(4, 0x07064b50), le(4, 0), le(8, record), le(4, 1)]));
  }
  const count = o.zip64 ? 0xffff : n;
  tail.push(concat([le(4, 0x06054b50), le(2, 0), le(2, 0), le(2, count), le(2, count), le(4, o.zip64 ? 0xffffffff : dir.length), le(4, o.zip64 ? 0xffffffff : offset), le(2, o.comment ?? 0), new Uint8Array(o.comment ?? 0)]));
  return concat([...parts, dir, ...tail]);
}

const gz = (s: string | Uint8Array) => new Uint8Array(gzipSync(typeof s === "string" ? enc(s) : s));
const LAYER = '{"layerType":"3DObject","name":"x"}';
const FILES: File[] = [
  { name: "3dSceneLayer.json.gz", data: gz(LAYER) },
  { name: "nodepages/0.json.gz", data: gz('{"nodes":[]}') },
  { name: "nodes/1/geometries/0.bin.gz", data: gz(Uint8Array.of(1, 2, 3, 4)) },
  { name: "nodes/1/textures/0.jpg", data: Uint8Array.of(0xff, 0xd8, 0xff, 0) },
  { name: "nodes/1/textures/0_0_1.bin.dds", data: enc("DDS ") },
  { name: "nodes/1/attributes/f_2/0.bin.gz", data: gz(Uint8Array.of(9, 8)) },
  { name: "statistics/f_2/0.json.gz", data: gz("{}"), method: 8 },
];
const EXPECTED: [string, Uint8Array][] = [
  ["layer", enc(LAYER)],
  ["nodepages/0", enc('{"nodes":[]}')],
  ["nodes/1/geometries/0", Uint8Array.of(1, 2, 3, 4)],
  ["nodes/1/textures/0", Uint8Array.of(0xff, 0xd8, 0xff, 0)],
  ["nodes/1/textures/0_0_1", enc("DDS ")],
  ["nodes/1/attributes/f_2/0", Uint8Array.of(9, 8)],
  ["statistics/f_2/0", enc("{}")],
];

/** A fake server of `file` that answers ranges (or refuses them), counting requests and bytes. */
function server(file: Uint8Array, { ranges = true, exposeRange = true } = {}) {
  const log = { requests: 0, bytes: 0 };
  const fetchRange: FetchRange = async (_url, init) => {
    log.requests++;
    if (init.method === "HEAD") return new Response(null, { headers: { "content-length": String(file.length) } });
    const range = new Headers(init.headers).get("range");
    if (!ranges || !range) {
      log.bytes += file.length;
      return new Response(file.slice(), { status: 200 });
    }
    const m = /^bytes=(\d*)-(\d*)$/.exec(range)!;
    const [s, e] = m[1] === "" ? [Math.max(0, file.length - Number(m[2])), file.length - 1] : [Number(m[1]), Math.min(file.length - 1, Number(m[2]))];
    const body = file.slice(s, e + 1);
    log.bytes += body.length;
    const headers: Record<string, string> = exposeRange ? { "content-range": `bytes ${s}-${e}/${file.length}` } : {};
    return new Response(body, { status: 206, headers });
  };
  return { fetchRange, log };
}

async function check(file: Uint8Array, open: () => ReturnType<typeof openSlpk>, index?: "hash" | "directory") {
  const s = await open();
  if (index) assert.equal(s.index, index);
  for (const [path, want] of EXPECTED) assert.deepEqual(await s.get(path), want, path);
  assert.equal(await s.get("nodes/9/geometries/0"), undefined);
  assert.equal(s.size, file.length);
  return s;
}

test("md5 matches node:crypto", () => {
  for (const s of ["", "a", "3dscenelayer.json.gz", "x".repeat(55), "y".repeat(56), "z".repeat(64), "地図".repeat(100)]) {
    assert.equal(Buffer.from(md5(enc(s))).toString("hex"), createHash("md5").update(s).digest("hex"));
  }
});

test("slpkCandidates maps REST paths to entries", () => {
  assert.deepEqual(slpkCandidates("layer"), ["3dSceneLayer.json.gz", "3dSceneLayer.json"]);
  assert.deepEqual(slpkCandidates("/nodepages/3"), ["nodepages/3.json.gz", "nodepages/3.json"]);
  assert.equal(slpkCandidates("nodes/5/geometries/1")[0], "nodes/5/geometries/1.bin.gz");
  assert.ok(slpkCandidates("nodes/5/textures/0").includes("nodes/5/textures/0.bin.dds"));
  assert.equal(slpkCandidates("nodes/5/attributes/f_2/0")[0], "nodes/5/attributes/f_2/0.bin.gz");
  assert.deepEqual(slpkCandidates("nodes/root"), ["nodes/root/3dNodeIndexDocument.json.gz"]);
  assert.equal(slpkCandidates("metadata")[0], "metadata");
});

test("openSlpk reads bytes, Blobs and URLs, with and without zip64 and the hash table", async () => {
  for (const zip64 of [false, true]) {
    for (const hash of [false, true]) {
      const file = slpk(FILES, { zip64, hash, filler: 3000 });
      await check(file, () => openSlpk(file), hash ? "hash" : "directory");
      await check(file, () => openSlpk(file.buffer as ArrayBuffer), hash ? "hash" : "directory");
      await check(file, () => openSlpk(new Blob([file])), hash ? "hash" : "directory");
      const { fetchRange, log } = server(file);
      const s = await check(file, () => openSlpk("https://x/a.slpk", fetchRange), hash ? "hash" : "directory");
      assert.equal(s.mode, "range");
      assert.ok(log.bytes < file.length / 2, `${log.bytes} of ${file.length} bytes read`);
    }
  }
});

test("openSlpk reads the directory from the first read when it is there, the hash table aside", async () => {
  const file = slpk(FILES, { hash: true });
  const { fetchRange, log } = server(file);
  const s = await check(file, () => openSlpk("https://x/a.slpk", fetchRange), "directory");
  assert.equal(log.requests, 1);
  assert.equal(s.mode, "range");
});

test("openSlpk reads the whole file when ranges are refused, and finds the size by HEAD without Content-Range", async () => {
  const file = slpk(FILES, { hash: true, filler: 3000 });
  const whole = server(file, { ranges: false });
  const s = await check(file, () => openSlpk("https://x/a.slpk", whole.fetchRange));
  assert.equal(s.mode, "whole");
  assert.equal(whole.log.requests, 1);
  const hidden = server(file, { exposeRange: false });
  await check(file, () => openSlpk("https://x/a.slpk", hidden.fetchRange), "hash");
});

test("openSlpk coalesces requests for the same entry and keeps recent ones", async () => {
  const file = slpk(FILES, { hash: true, filler: 3000 });
  const { fetchRange, log } = server(file);
  const s = await openSlpk("https://x/a.slpk", fetchRange);
  const before = log.requests;
  const [a, b] = await Promise.all([s.get("nodes/1/geometries/0"), s.get("nodes/1/geometries/0")]);
  assert.deepEqual(a, b);
  const once = log.requests - before;
  await s.get("nodes/1/geometries/0");
  assert.equal(log.requests - before, once);
});

test("slpkResources gives JSON and bytes by path or by URL under SLPK_URL", async () => {
  const r = slpkResources(await openSlpk(slpk(FILES)));
  assert.equal(r.url, SLPK_URL);
  assert.deepEqual(await r.json("layer"), JSON.parse(LAYER));
  assert.deepEqual(await r.json(`${SLPK_URL}nodepages/0?token=t`), { nodes: [] });
  assert.deepEqual(await r.bytes(`${SLPK_URL}nodes/1/geometries/0`), Uint8Array.of(1, 2, 3, 4));
  await assert.rejects(r.bytes("nodes/2/geometries/0"), /no nodes\/2\/geometries\/0/);
});

test("openSlpk refuses malformed and hostile archives", async () => {
  const file = slpk(FILES);
  const set = (b: Uint8Array, at: number, bytes: number, value: number) => {
    const c = b.slice();
    const v = new DataView(c.buffer);
    if (bytes === 2) v.setUint16(at, value, true);
    else v.setUint32(at, value, true);
    return c;
  };
  const eocd = file.length - 22;
  await assert.rejects(openSlpk(enc("PK no end")), /not a zip archive/);
  await assert.rejects(openSlpk(file.subarray(0, file.length - 5)), /not a zip archive/);
  await assert.rejects(openSlpk(set(file, eocd + 4, 2, 1)), /split archives/);
  await assert.rejects(openSlpk(set(file, eocd + 10, 2, 0xffff)), /zip64 archive without its end record/);
  await assert.rejects(openSlpk(set(file, eocd + 16, 4, file.length)), /central directory past its end record/);
  await assert.rejects(openSlpk(set(file, eocd + 12, 4, 0x7fffffff)), /central directory over/);
  await assert.rejects(openSlpk(set(file, eocd + 10, 2, 300)), /malformed central directory/);
  const dir = new DataView(file.buffer).getUint32(eocd + 16, true);
  // The second entry pointing at the first one's data (a zip bomb's overlap), and past the directory.
  await assert.rejects(openSlpk(set(file, dir + 46 + FILES[0].name.length + 42, 4, 0)), /overlaps/);
  await assert.rejects(openSlpk(set(file, dir + 42, 4, dir + 10)), /overlaps/);
  const sizes = set(set(file, dir + 20, 4, 0x7fffffff), dir + 24, 4, 0x7fffffff);
  await assert.rejects(openSlpk(sizes), /over \d+ bytes/);
  // A local header that is not one, of another name, or a method that is not read.
  const local = set(file, 0, 4, 0);
  await assert.rejects((await openSlpk(local)).get("layer"), /malformed local header/);
  const renamed = file.slice();
  renamed[30] = "4".charCodeAt(0);
  await assert.rejects((await openSlpk(renamed)).get("layer"), /local header of another name/);
  await assert.rejects((await openSlpk(set(set(file, 8, 2, 12), dir + 10, 2, 12))).get("layer"), /method 12/);
  // A zip64 locator naming a record past it, or one that is not.
  const big = slpk(FILES, { zip64: true });
  const loc = big.length - 22 - 20;
  await assert.rejects(openSlpk(set(big, loc + 8, 4, big.length)), /zip64 end record past/);
  await assert.rejects(openSlpk(set(big, loc + 8, 4, 0)), /malformed zip64 end record/);
});

test("openSlpk refuses hash tables pointing past the directory and leaves unsorted ones", async () => {
  const files = FILES.slice(0, 2);
  const hashed = slpk(files, { hash: true, filler: 3000 });
  // The table is the last entry's data, just before the padding.
  const rows = files.length + 3000;
  const start = Buffer.from(hashed).indexOf("@specialIndexFileHASH128@") + 25;
  const v = new DataView(hashed.buffer);
  assert.equal(new TextDecoder().decode(hashed.subarray(start - 25, start)), "@specialIndexFileHASH128@");
  const past = hashed.slice();
  for (let i = 0; i < rows; i++) new DataView(past.buffer).setUint32(start + i * 24 + 16, hashed.length, true);
  await assert.rejects((await openSlpk(new Blob([past]))).get("layer"), /entry past the directory/);
  const misdirected = hashed.slice();
  for (let i = 0; i < rows; i++) new DataView(misdirected.buffer).setUint32(start + i * 24 + 16, 0, true);
  await assert.rejects((await openSlpk(new Blob([misdirected]))).get("nodepages/0"), /nodepages\/0.json.gz: a local header of another name/);
  // A data descriptor leaves the local header without sizes: the directory gives them.
  const described = hashed.slice();
  described[30 + FILES[0].name.length + FILES[0].data.length + 6] |= 8;
  const d = await openSlpk(new Blob([described]));
  assert.equal(d.index, "hash");
  assert.deepEqual(await d.get("nodepages/0"), enc('{"nodes":[]}'));
  const unsorted = hashed.slice();
  unsorted.copyWithin(start, start + 24, start + 48);
  unsorted.set(hashed.subarray(start, start + 24), start + 24);
  const swapped = v.getBigUint64(start, true) !== v.getBigUint64(start + 24, true);
  assert.ok(swapped);
  const s = await openSlpk(new Blob([unsorted]));
  assert.equal(s.index, "directory");
  assert.deepEqual(await s.get("layer"), enc(LAYER));
});

test("openSlpk caps what a gzipped entry inflates to", async () => {
  const bomb = slpk([{ name: "nodes/1/geometries/0.bin.gz", data: gz(new Uint8Array(300 << 20)) }]);
  await assert.rejects((await openSlpk(bomb)).get("nodes/1/geometries/0"), /inflates past/);
});

test("openSlpk refuses a range answered with other bytes", async () => {
  const file = slpk(FILES, { hash: true, filler: 3000 });
  const lying: FetchRange = async (url, init) => {
    const range = new Headers(init.headers).get("range")!;
    if (range.startsWith("bytes=-")) return server(file).fetchRange(url, init);
    return new Response(new Uint8Array(4), { status: 206, headers: { "content-range": `bytes 0-3/${file.length}` } });
  };
  await assert.rejects(openSlpk("https://x/a.slpk", lying).then((s) => s.get("layer")), /range other than asked/);
  const failing: FetchRange = async () => new Response(null, { status: 404 });
  await assert.rejects(openSlpk("https://x/a.slpk", failing), /HTTP 404/);
});
