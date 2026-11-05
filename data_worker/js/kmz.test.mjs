import assert from "node:assert/strict";
import { test } from "node:test";
import { deflateRawSync } from "node:zlib";
import { entryBytes, isZip, kmlOfKmz, zipEntries } from "./kmz.mjs";

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
    const m = method ?? (store ? 0 : 8);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(m, 8);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(n.length, 26);
    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt16LE(flags, 8);
    cd.writeUInt16LE(m, 10);
    cd.writeUInt32LE(body.length, 20);
    cd.writeUInt32LE(data.length, 24);
    cd.writeUInt16LE(n.length, 28);
    cd.writeUInt32LE(offset, 42);
    parts.push(local, n, body);
    central.push(cd, n);
    offset += 30 + n.length + body.length;
  }
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(central.reduce((s, b) => s + b.length, 0), 12);
  end.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...parts, ...central, end]));
}

test("zipEntries lists stored and deflated entries", async () => {
  const bytes = zip([{ name: "a.txt", data: encoder.encode("stored"), store: true }, { name: "dir/b.kml", data: encoder.encode("deflated".repeat(10)) }]);
  assert.ok(isZip(bytes));
  assert.ok(!isZip(encoder.encode("<kml/>")));
  const entries = zipEntries(bytes);
  assert.deepEqual(entries.map((e) => [e.name, e.method, e.size]), [["a.txt", 0, 6], ["dir/b.kml", 8, 80]]);
  assert.equal(decoder.decode(await entryBytes(bytes, entries[0], 100)), "stored");
  assert.equal(decoder.decode(await entryBytes(bytes, entries[1], 100)), "deflated".repeat(10));
});

test("kmlOfKmz takes doc.kml, else the first .kml", async () => {
  const one = zip([{ name: "files/x.kml", data: encoder.encode("first") }, { name: "DOC.KML", data: encoder.encode("doc") }]);
  assert.equal(decoder.decode(await kmlOfKmz(one, 100)), "doc");
  const two = zip([{ name: "a.png", data: new Uint8Array(3) }, { name: "x/first.KML", data: encoder.encode("first") }, { name: "second.kml", data: encoder.encode("second") }]);
  assert.equal(decoder.decode(await kmlOfKmz(two, 100)), "first");
  await assert.rejects(kmlOfKmz(zip([{ name: "a.png", data: new Uint8Array(3) }]), 100), /no \.kml/);
});

test("malformed, encrypted, unknown and oversized entries are refused", async () => {
  const bytes = zip([{ name: "doc.kml", data: encoder.encode("<kml/>".repeat(100)) }]);
  assert.throws(() => zipEntries(bytes.subarray(0, 40)), /no end of central directory/);
  const moved = bytes.slice();
  moved[moved.length - 6] = 0xff;
  assert.throws(() => zipEntries(moved), /malformed zip/);
  await assert.rejects(kmlOfKmz(bytes, 100), /inflates past 100 bytes/);
  await assert.rejects(kmlOfKmz(zip([{ name: "doc.kml", data: encoder.encode("x"), flags: 1 }]), 100), /encrypted/);
  await assert.rejects(kmlOfKmz(zip([{ name: "doc.kml", data: encoder.encode("x"), store: true, method: 12 }]), 100), /method 12/);
  await assert.rejects(kmlOfKmz(zip([{ name: "doc.kml", data: encoder.encode("x".repeat(200)), store: true }]), 100), /larger than 100/);
});
