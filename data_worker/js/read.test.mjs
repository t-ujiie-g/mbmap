import assert from "node:assert/strict";
import test from "node:test";
import { deflateRawSync } from "node:zlib";
import { dataImports, dbfEncoding, isCrs, isZip, kmlOfKmz, rasterSource } from "./read.mjs";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

// A zip of `entries` ({ name, data, store, flags, method }) as an archiver writes one.
function zip(entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const { name, data, store, flags = 0, method } of entries) {
    const n = encoder.encode(name);
    const body = store ? data : deflateRawSync(data);
    const header = (size, at) => {
      const b = Buffer.alloc(size);
      b.writeUInt16LE(flags, at);
      b.writeUInt16LE(method ?? (store ? 0 : 8), at + 2);
      b.writeUInt32LE(body.length, at + 12);
      b.writeUInt32LE(data.length, at + 16);
      b.writeUInt16LE(n.length, at + 20);
      return b;
    };
    const local = header(30, 6);
    local.writeUInt32LE(0x04034b50, 0);
    const cd = header(46, 8);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt32LE(offset, 42);
    parts.push(local, n, body);
    central.push(cd, n);
    offset += 30 + n.length + body.length;
  }
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(central.reduce((s, b) => s + b.length, 0), 12);
  end.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...parts, ...central, end]));
}

test("dbfEncoding takes the option, then the .cpg, then the language driver, then UTF-8", () => {
  for (const cpg of ["SJIS", "CP932", "ANSI 932", "Shift_JIS", "932\r\n", " windows-31j "]) assert.equal(dbfEncoding(undefined, cpg, null), "shift_jis");
  assert.equal(dbfEncoding(undefined, "UTF-8", null), "utf-8");
  assert.equal(dbfEncoding(undefined, "65001", null), "utf-8");
  assert.equal(dbfEncoding(undefined, "1252", null), "windows-1252");
  assert.equal(dbfEncoding(undefined, "CP1251", null), "windows-1251");
  assert.equal(dbfEncoding(undefined, "ISO-8859-1", null), "windows-1252");
  assert.equal(dbfEncoding(undefined, "28595", null), "iso-8859-5");
  assert.equal(dbfEncoding(undefined, "EUC-JP", null), "euc-jp");
  assert.equal(dbfEncoding("cp936", "UTF-8", null), "gbk");
  const ldid = (b) => Object.assign(new Uint8Array(32), { 29: b });
  assert.equal(dbfEncoding(undefined, undefined, ldid(0x13)), "shift_jis");
  assert.equal(dbfEncoding(undefined, "nonsense", ldid(0x7b)), "shift_jis");
  assert.equal(dbfEncoding(undefined, undefined, ldid(0x57)), "utf-8");
  assert.equal(dbfEncoding(undefined, "437", ldid(0)), "utf-8");
});

test("isZip tells archives by their first bytes", () => {
  assert.equal(isZip(Uint8Array.of(0x50, 0x4b, 3, 4)), true);
  assert.equal(isZip(Uint8Array.of(0x50, 0x4b, 5, 6)), true);
  assert.equal(isZip(Uint8Array.of(0, 0, 0x27, 0x0a)), false);
  assert.equal(isZip(Uint8Array.of(0x50, 0x4b)), false);
});

test("dataImports decodes DBF text in the decoder it is given, NULs removed and trimmed", () => {
  const memory = { buffer: new Uint8Array([0x20, 0x92, 0x6e, 0x00, 0x90, 0x7d, 0x20]).buffer };
  const { host } = dataImports(() => memory);
  host.decoder = new TextDecoder("shift_jis");
  const n = host.decode(0, 7);
  assert.equal(String.fromCharCode(...Array.from({ length: n }, (_, i) => host.text_code(i))), "地図");
});

test("kmlOfKmz takes doc.kml at the top, else the first .kml", async () => {
  const one = zip([{ name: "files/x.kml", data: encoder.encode("first") }, { name: "DOC.KML", data: encoder.encode("doc") }]);
  assert.equal(decoder.decode(await kmlOfKmz(one)), "doc");
  const two = zip([{ name: "a.png", data: new Uint8Array(3) }, { name: "x/first.KML", data: encoder.encode("first"), store: true }, { name: "second.kml", data: encoder.encode("second") }]);
  assert.equal(decoder.decode(await kmlOfKmz(two)), "first");
  await assert.rejects(kmlOfKmz(zip([{ name: "a.png", data: new Uint8Array(3) }])), /no \.kml file/);
});

test("kmlOfKmz refuses malformed, encrypted, unknown and oversized entries", async () => {
  const bytes = zip([{ name: "doc.kml", data: encoder.encode("<kml/>".repeat(100)) }]);
  await assert.rejects(kmlOfKmz(bytes.subarray(0, 40)), /not a zip archive/);
  await assert.rejects(kmlOfKmz(bytes, 100), /inflates to more than 100 bytes/);
  await assert.rejects(kmlOfKmz(zip([{ name: "doc.kml", data: encoder.encode("x"), flags: 1 }])), /encrypted/);
  await assert.rejects(kmlOfKmz(zip([{ name: "doc.kml", data: encoder.encode("x"), store: true, method: 12 }])), /method 12/);
});

test("isCrs takes an EPSG code or a definition of 34 slots", () => {
  assert.ok(isCrs(6677));
  assert.ok(isCrs(new Float64Array(34)));
  for (const bad of [0, -1, 1.5, "6677", null, new Float64Array(33), new Float64Array(35), new Float32Array(34)]) assert.ok(!isCrs(bad));
});

test("a raster source by URL is kept apart by what its requests send", () => {
  const key = (init) => rasterSource({ url: "https://x.org/a.tif", init }, 100).key;
  assert.equal(key(undefined), key({}));
  assert.equal(key({ headers: { a: "1" } }), key({ headers: { a: "1" } }));
  assert.notEqual(key(undefined), key({ headers: { a: "1" } }));
  assert.notEqual(key({ headers: { a: "1" } }), key({ headers: { a: "2" } }));
  assert.notEqual(key(undefined), key({ credentials: "include" }));
});

test("a raster source's range requests time out", async (t) => {
  let options;
  t.mock.method(globalThis, "fetch", async (_, o) => {
    options = o;
    return new Response(new Uint8Array(4), { status: 206, headers: { "content-range": "bytes 8-11/100" } });
  });
  const bytes = await rasterSource({ url: "https://x.org/a.tif" }, 100).read(8, 4);
  assert.equal(bytes.length, 4);
  assert.ok(options.signal instanceof AbortSignal);
  assert.equal(options.headers.Range, "bytes=8-11");
});

// Answers ranges of `file` by the mock's fetch; `answer(from)` may give a Response instead.
function serve(t, file, answer = () => undefined) {
  t.mock.method(globalThis, "fetch", async (_, { headers }) => {
    const [, from, to] = /^bytes=(\d+)-(\d+)$/.exec(headers.Range).map(Number);
    const end = Math.min(to + 1, file.length);
    return answer(from) ?? new Response(file.subarray(from, end), { status: 206, headers: { "content-range": `bytes ${from}-${end - 1}/${file.length}` } });
  });
}

const FILE = Uint8Array.from({ length: 64 }, (_, i) => i);
const source = (max = 1000) => rasterSource({ url: "https://x.org/a.tif" }, max);

test("a raster source reads the range it is answered", async (t) => {
  serve(t, FILE);
  assert.deepEqual(Array.from(await source().read(8, 4)), [8, 9, 10, 11]);
});

test("a raster source takes a 200 as the whole file, up to max", async (t) => {
  serve(t, FILE, () => new Response(FILE));
  assert.deepEqual(await source().read(8, 4), { whole: FILE });
  await assert.rejects(source(63).read(8, 4), /response larger than 63 bytes/);
});

test("a raster source refuses another range and any other status", async (t) => {
  serve(t, FILE, (from) => new Response(FILE, { status: 206, headers: { "content-range": `bytes ${from + 1}-20/64` } }));
  await assert.rejects(source().read(8, 4), /^Error: https:\/\/x\.org\/a\.tif answered another range$/);
  t.mock.restoreAll();
  serve(t, FILE, () => new Response(FILE, { status: 206 }));
  await assert.rejects(source().read(8, 4), /answered another range/);
  t.mock.restoreAll();
  serve(t, FILE, () => new Response(null, { status: 404 }));
  await assert.rejects(source().read(8, 4), /^Error: HTTP 404 for https:\/\/x\.org\/a\.tif$/);
});

test("a raster source reads no more of a range than it asked for", async (t) => {
  serve(t, FILE, () => new Response(FILE, { status: 206, headers: { "content-range": "bytes 8-63/64" } }));
  await assert.rejects(source().read(8, 4), /response larger than 4 bytes/);
});
